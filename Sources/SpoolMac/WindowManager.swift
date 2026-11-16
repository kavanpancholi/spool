import AppKit
import ApplicationServices
import Combine
import OSLog
import QuartzCore
import SpoolCore

struct StripKey: Hashable {
  let display: String
  let space: UInt64
}

final class ManagedWindow {
  let id: WindowID
  let element: AXUIElement
  let pid: pid_t
  let bundleID: String?
  let cgID: CGWindowID?
  let isPrompt: Bool
  lazy var cornerRadius: Double = AX.cornerRadius(of: element)

  init(id: WindowID, element: AXUIElement, pid: pid_t, bundleID: String?, cgID: CGWindowID?, isPrompt: Bool) {
    self.id = id
    self.element = element
    self.pid = pid
    self.bundleID = bundleID
    self.cgID = cgID
    self.isPrompt = isPrompt
  }
}

public final class WindowManager {
  public private(set) var isRunning = false
  public private(set) var failedShortcuts: [Shortcut] = []
  public var onStateChange: (() -> Void)?

  private let store: SettingsStore
  private var settings: SpoolSettings { store.settings }
  private let log = Logger(subsystem: "io.github.kavanpancholi.spool", category: "manager")

  private let writer = FrameWriter()
  private let input = InputTap()
  private let hotKeys = HotKeys()
  private let bars = BarController()
  private let workspaceBadge = WorkspaceBadge()
  private let staircase = DisplayStaircase()
  private let decorations = Decorations()
  private let modifierHold = ModifierHold()
  private let cheatsheet = CheatsheetPanel()
  private var focusHistory = FocusHistory()
  private var focusedID: WindowID?
  private var decorateQueued = false
  private let sessionStore = SessionStore()
  private var pendingRestore = false
  private var swiping: Set<StripKey> = []
  private var barRefreshQueued = false
  private let focusQueue = DispatchQueue(label: "Spool focus", qos: .userInteractive)
  private let focusGeneration = Generation()

  private var observers: [pid_t: AppObserver] = [:]
  private var windows: [WindowID: ManagedWindow] = [:]
  private var nextID: WindowID = 1
  private var displays: [Display] = []
  private var activeKeys: [String: StripKey] = [:]
  private var spanDisplay: Display?
  private var spanParts: [Display] = []
  private var separateSpaces = true
  private var strips: [StripKey: Strip] = [:]
  private var hidden: [StripKey: Workspaces] = [:]
  private var appsWithTiles: [pid_t] = []
  private static let appTileBase: WindowID = 1 << 62
  private var springs: [StripKey: Spring] = [:]
  private var lastTargets: [WindowID: CGRect] = [:]
  private var manuallyFloating: Set<WindowID> = []
  private var corrections: [WindowID: Int] = [:]
  private var parked: Set<WindowID> = []
  private var pendingFrameChecks: Set<WindowID> = []
  private var draggedWindows: Set<WindowID> = []
  private var minimizedIDs: Set<WindowID> = []

  private var animationTimer: Timer?
  private var lastTick = CACurrentMediaTime()
  private var snapTimers: [StripKey: Timer] = [:]
  private var rebuildTimer: Timer?
  private var displayWatch: Timer?
  private var lastManualScroll = Date.distantPast
  private var workspaceTokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var cancellables: Set<AnyCancellable> = []

  public init(store: SettingsStore) {
    self.store = store
    hotKeys.onCommand = { [weak self] command in self?.perform(command) }
    failedShortcuts = hotKeys.register(Shortcut.defaults)
    input.onWheel = { [weak self] delta, point in self?.wheel(delta, at: point) ?? false }
    input.onSwipe = { [weak self] phase, point in self?.swipe(phase, at: point) }
    bars.onSelect = { [weak self] id in self?.reveal(id) }
    bars.onMove = { [weak self] id, display, index in self?.moveTile(id, toDisplay: display, index: index) }
    bars.label = { [weak self] id in self?.label(for: id) ?? "" }
    modifierHold.onHold = { [weak self] in self?.showCheatsheet() }
    modifierHold.onRelease = { [weak self] in self?.cheatsheet.hide() }
    store.$settings
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.settingsChanged() }
      .store(in: &cancellables)
  }


  public func start() {
    guard !isRunning, AXIsProcessTrusted() else { return }
    isRunning = true
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    input.thumbWheel = settings.thumbWheel
    input.trackpad = settings.trackpad
    if !input.start() {
      log.error("Event tap could not start; thumb wheel and swipes are off")
    }
    observeWorkspace()
    for app in NSWorkspace.shared.runningApplications where Self.isManageable(app) {
      track(app, discover: false)
    }
    staircase.start { [weak self] in self?.scheduleRebuild(after: 0.1) }
    pendingRestore = true
    if settings.cheatsheetOnHold { modifierHold.start() }
    rebuild(resetOrder: true)
    displayWatch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      guard let self, Display.current() != self.displays else { return }
      self.scheduleRebuild(after: 0.1)
    }
    log.info("Spool started with \(self.windows.count) windows")
    onStateChange?()
  }

  public func stop() {
    guard isRunning else { return }
    isRunning = false
    input.stop()
    animationTimer?.invalidate()
    animationTimer = nil
    snapTimers.values.forEach { $0.invalidate() }
    snapTimers.removeAll()
    rebuildTimer?.invalidate()
    displayWatch?.invalidate()
    displayWatch = nil
    for (center, token) in workspaceTokens { center.removeObserver(token) }
    workspaceTokens.removeAll()
    saveSession()
    sessionStore.save()
    restoreAllWindows()
    staircase.stop()
    modifierHold.stop()
    cheatsheet.hide()
    workspaceBadge.hide()
    decorations.hideAll()
    focusedID = nil
    bars.hideAll()
    swiping.removeAll()
    observers.removeAll()
    windows.values.forEach { writer.forget($0.id) }
    windows.removeAll()
    strips.removeAll()
    hidden.removeAll()
    appsWithTiles.removeAll()
    springs.removeAll()
    activeKeys.removeAll()
    lastTargets.removeAll()
    parked.removeAll()
    corrections.removeAll()
    manuallyFloating.removeAll()
    minimizedIDs.removeAll()
    draggedWindows.removeAll()
    log.info("Spool stopped")
    onStateChange?()
  }

  public func rearrange() {
    guard isRunning else { return }
    strips.removeAll()
    springs.removeAll()
    rebuild(resetOrder: true)
  }

  private func settingsChanged() {
    if settings.enabled != isRunning {
      settings.enabled ? start() : stop()
      return
    }
    input.thumbWheel = settings.thumbWheel
    input.trackpad = settings.trackpad
    guard isRunning else { return }
    if settings.cheatsheetOnHold { modifierHold.start() } else { modifierHold.stop() }
    rebuild(resetOrder: false)
    decorate(reorder: true)
  }


  public func perform(_ command: Command) {
    modifierHold.cancel()
    if command == .toggleEnabled {
      store.settings.enabled.toggle()
      return
    }
    guard isRunning, let key = commandKey(), var strip = strips[key], let display = display(for: key) else { return }

    switch command {
    case .sendToNextDisplay:
      sendToNextDisplay(from: key)
    case .toggleFloat:
      toggleFloat()
    case .keepOwnHeight:
      guard let index = strip.focusedColumn, let id = strip.focusedWindow, let window = windows[id] else { return }
      if strip.columns[index].fixedHeight != nil {
        strip.columns[index].fixedHeight = nil
      } else if strip.columns[index].windows.count == 1, let frame = AX.frame(window.element) {
        strip.columns[index].fixedHeight = frame.height
      } else {
        return
      }
      strips[key] = strip
      writer.invalidate(id)
      relayout(key, animated: false)
    case .focusFloating:
      focusNextFloating()
    case .focusWorkspace(let direction):
      var stack = hidden[key] ?? Workspaces()
      let target = direction == .down ? stack.switchDown(from: strip) : direction == .up ? stack.switchUp(from: strip) : nil
      guard let target else { return }
      showWorkspace(target, stack, key)
    case .moveToWorkspace(let direction):
      var stack = hidden[key] ?? Workspaces()
      guard let target = stack.moveFocused(direction, from: &strip) else { return }
      showWorkspace(target, stack, key)
    case .focusPrevious:
      let current = focusedManagedWindow()?.id
      if let id = focusHistory.previous(current: current, where: { windows[$0] != nil && !minimizedIDs.contains($0) }) {
        reveal(id)
      }
    default:
      let result = strip.apply(command, settings: settings.forDisplay(display.uuid), geometry: geometry(display))
      guard result.handled else { return }
      strips[key] = strip
      if result.layoutChanged { relayout(key, animated: true) }
      if result.focusChanged, let id = strip.focusedWindow { focus(id) }
    }
  }

  private func showWorkspace(_ strip: Strip, _ stack: Workspaces, _ key: StripKey) {
    guard let display = display(for: key) else { return }
    var strip = strip
    if let index = strip.focusedColumn {
      strip.scroll = revealScroll(strip, column: index, display)
    }
    strips[key] = strip
    hidden[key] = stack.isEmpty ? nil : stack
    parkHidden(key)
    relayout(key, animated: false)
    if let id = strip.focusedWindow { focus(id) }
    showWorkspaceBadge(stack.position(current: strip), on: display)
  }

  private func showWorkspaceBadge(_ position: (index: Int, count: Int), on display: Display) {
    guard position.count > 1 else { return }
    workspaceBadge.show(index: position.index, count: position.count, on: display.visibleFrame)
  }

  private func parkHidden(_ key: StripKey) {
    guard activeKeys[key.display] == key, let stack = hidden[key], let display = display(for: key) else { return }
    let context = context(display)
    for strip in stack.above + stack.below {
      for (id, placement) in strip.hiddenLayout(context) {
        guard let window = windows[id] else { continue }
        parked.insert(id)
        lastTargets[id] = placement.frame
        writer.submit(window.element, pid: window.pid, id: id, frame: placement.frame)
      }
    }
  }

  private func hiddenKey(containing id: WindowID) -> StripKey? {
    hidden.first { $0.value.contains(id) }?.key
  }

  private func showHiddenWorkspace(containing id: WindowID) -> Bool {
    guard let key = hiddenKey(containing: id), activeKeys[key.display] == key, var stack = hidden[key],
      let target = stack.switchTo(containing: id, from: strips[key] ?? Strip())
    else { return false }
    var strip = target
    strip.focus(window: id)
    showWorkspace(strip, stack, key)
    return true
  }

  private func focusNextFloating() {
    let tiled = Set(strips.values.flatMap(\.windows) + hidden.values.flatMap(\.windows))
    let onScreen = Spaces.onScreenWindowIDs()
    let floating = windows.values
      .filter { !tiled.contains($0.id) && !minimizedIDs.contains($0.id) && $0.cgID.map(onScreen.contains) == true }
      .map(\.id)
      .sorted()
    guard !floating.isEmpty else { return }
    let current = focusedManagedWindow()?.id
    let next = current.flatMap { floating.firstIndex(of: $0) }.map { floating[($0 + 1) % floating.count] } ?? floating[0]
    focus(next)
  }

  private func commandKey() -> StripKey? {
    if let focused = focusedManagedWindow(), let key = activeKey(containing: focused.id) {
      return key
    }
    let mouse = Self.quartzMouseLocation()
    let display = displays.first { $0.contains(mouse) } ?? displays.first
    return display.flatMap { activeKeys[$0.uuid] }
  }

  private func sendToNextDisplay(from key: StripKey) {
    let ordered = displays.filter { activeKeys[$0.uuid] != nil }.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    guard ordered.count > 1,
      var source = strips[key],
      let id = source.focusedWindow,
      let sourceIndex = ordered.firstIndex(where: { $0.uuid == key.display }),
      let sourceColumn = source.columnIndex(of: id)
    else { return }
    let width = source.columns[sourceColumn].width
    let target = ordered[(sourceIndex + 1) % ordered.count]
    guard let targetKey = activeKeys[target.uuid] else { return }

    source.remove(id)
    if let index = source.focusedColumn {
      source.scroll = source.revealScroll(column: index, mode: settings.centerMode, geometry(ordered[sourceIndex]))
    }
    strips[key] = source

    var destination = strips[targetKey] ?? Strip()
    destination.insert(id, width: width, focus: true)
    if let index = destination.focusedColumn {
      destination.scroll = revealScroll(destination, column: index, target)
    }
    strips[targetKey] = destination
    relayout(key, animated: true)
    relayout(targetKey, animated: false)
    focus(id)
  }

  private func toggleFloat() {
    guard let window = focusedManagedWindow() else { return }
    if let key = activeKey(containing: window.id), var strip = strips[key] {
      strip.remove(window.id)
      strips[key] = strip
      manuallyFloating.insert(window.id)
      relayout(key, animated: true)
      if let display = display(for: key), let frame = AX.frame(window.element) {
        let visible = display.visibleFrame
        let size = CGSize(width: min(frame.width, visible.width * 0.6), height: min(frame.height, visible.height * 0.7))
        writer.submit(window.element, pid: window.pid, id: window.id, frame: CGRect(
          x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height
        ))
      }
    } else if manuallyFloating.remove(window.id) != nil {
      addWindow(window.element, pid: window.pid, attempt: 0)
    }
  }


  private func observeWorkspace() {
    let center = NSWorkspace.shared.notificationCenter
    func on(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
      workspaceTokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: block)))
    }
    on(center, NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
      if Self.isManageable(app) { self?.track(app, discover: true) }
    }
    on(center, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
      self?.forget(pid: app.processIdentifier)
    }
    on(center, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
      self?.syncFocus()
    }
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
      on(center, name) { [weak self] _ in
        self?.scheduleBarRefresh()
        self?.scheduleRebuild(after: 0.25)
      }
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      on(center, name) { [weak self] _ in self?.scheduleWakeRebuilds() }
    }
    on(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] _ in
      self?.scheduleWakeRebuilds()
    }
    on(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
      self?.forgetWrittenFrames()
      self?.scheduleRebuild(after: 0.5)
    }
  }

  private func track(_ app: NSRunningApplication, discover: Bool, attempt: Int = 0) {
    let pid = app.processIdentifier
    guard isRunning, pid != getpid(), observers[pid] == nil, !app.isTerminated else { return }
    guard let observer = AppObserver(pid: pid, handler: { [weak self] event, element, pid in
      self?.handle(event, element, pid: pid)
    }) else {
      if attempt < 6 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.track(app, discover: discover, attempt: attempt + 1)
        }
      }
      return
    }
    observers[pid] = observer
    guard discover else { return }
    for element in AX.windows(of: observer.app) {
      addWindow(element, pid: pid, attempt: 0)
    }
  }

  private func forget(pid: pid_t) {
    observers[pid] = nil
    appsWithTiles.removeAll { $0 == pid }
    scheduleBarRefresh()
    let gone = windows.values.filter { $0.pid == pid }.map(\.id)
    gone.forEach { removeWindow($0) }
  }

  private func register(_ element: AXUIElement, pid: pid_t) -> ManagedWindow {
    if let existing = lookup(element, pid: pid) { return existing }
    let app = NSRunningApplication(processIdentifier: pid)
    let window = ManagedWindow(
      id: nextID,
      element: element,
      pid: pid,
      bundleID: app?.bundleIdentifier,
      cgID: AX.cgWindowID(element),
      isPrompt: app.map(Self.isSystemPrompt) ?? false
    )
    nextID += 1
    windows[window.id] = window
    observers[pid]?.watch(element)
    return window
  }

  private func lookup(_ element: AXUIElement, pid: pid_t) -> ManagedWindow? {
    let cgID = AX.cgWindowID(element)
    return windows.values.first { window in
      guard window.pid == pid else { return false }
      if let cgID, let other = window.cgID { return cgID == other }
      return CFEqual(window.element, element)
    }
  }

  private enum Tileability { case tile, never, notYet, minimized }

  private func tileability(_ window: ManagedWindow) -> Tileability {
    if manuallyFloating.contains(window.id) { return .never }
    if let bundleID = window.bundleID, settings.floatingBundleIDs.contains(bundleID) { return .never }
    let element = window.element
    if window.isPrompt {
      guard let frame = AX.frame(element) else { return .notYet }
      return frame.width >= 40 && frame.height >= 40 ? .tile : .never
    }
    let traits = WindowTraits(
      role: AX.value(element, kAXRoleAttribute),
      subrole: AX.value(element, kAXSubroleAttribute),
      identifier: AX.value(element, kAXIdentifierAttribute),
      hasCloseButton: AX.has(element, kAXCloseButtonAttribute),
      hasMinimizeButton: AX.has(element, kAXMinimizeButtonAttribute),
      isResizable: AX.isSettable(element, kAXSizeAttribute),
      isMovable: AX.isSettable(element, kAXPositionAttribute),
      isMinimized: AX.bool(element, kAXMinimizedAttribute),
      isFullScreen: AX.bool(element, "AXFullScreen"),
      size: AX.frame(element)?.size
    )
    if traits.isMinimized {
      var restored = traits
      restored.isMinimized = false
      return WindowRules.decide(restored) == .tile ? .minimized : .never
    }
    switch WindowRules.decide(traits) {
    case .tile: return .tile
    case .float: return .never
    case .notYet: return .notYet
    }
  }

  private func addWindow(_ element: AXUIElement, pid: pid_t, attempt: Int) {
    guard isRunning else { return }
    let window = register(element, pid: pid)

    switch tileability(window) {
    case .never:
      return
    case .minimized:
      minimizedIDs.insert(window.id)
      scheduleBarRefresh()
      return
    case .notYet:
      if attempt < 3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + [0.1, 0.3, 0.8][attempt]) { [weak self] in
          self?.addWindow(element, pid: pid, attempt: attempt + 1)
        }
      }
      return
    case .tile:
      minimizedIDs.remove(window.id)
    }

    if let cgID = window.cgID, !Spaces.onScreenWindowIDs().contains(cgID) {
      if attempt < 3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + [0.1, 0.3, 0.8][attempt]) { [weak self] in
          self?.addWindow(element, pid: pid, attempt: attempt + 1)
        }
      }
      return
    }
    guard activeKey(containing: window.id) == nil, hiddenKey(containing: window.id) == nil,
      let frame = AX.frame(element),
      let display = display(containing: frame),
      let key = activeKeys[display.uuid]
    else { return }

    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    let focused = window.isPrompt || (frontmost && focusedElement(of: pid).map { CFEqual($0, element) } == true)
    guard let stripDisplay = self.display(for: key) else { return }
    var strip = strips[key] ?? Strip()
    let geometry = geometry(stripDisplay)
    strip.insert(window.id, width: newColumnWidth(window, frame, stripDisplay), focus: focused)
    if window.isPrompt, let index = strip.columnIndex(of: window.id) {
      strip.columns[index].fixedHeight = frame.height
    }
    if focused, let index = strip.focusedColumn {
      strip.scroll = revealScroll(strip, column: index, stripDisplay)
    }
    strips[key] = strip
    relayout(key, animated: true)
    if window.isPrompt { focus(window.id) }
  }

  private func newColumnWidth(_ window: ManagedWindow, _ frame: CGRect, _ display: Display) -> Double {
    let geometry = geometry(display)
    if !window.isPrompt, let width = settings.forDisplay(display.uuid).defaultWidth {
      return width.fraction(in: geometry)
    }
    return columnWidth(frame, geometry)
  }

  private func columnWidth(_ frame: CGRect, _ geometry: StripGeometry) -> Double {
    min(1, max(0.1, geometry.fraction(forPoints: frame.width)))
  }

  private func removeWindow(_ id: WindowID) {
    removeFromHidden(id)
    for (key, var strip) in strips where strip.contains(id) {
      strip.remove(id)
      if let index = strip.focusedColumn, let display = display(for: key) {
        strip.scroll = revealScroll(strip, column: index, display)
      }
      strips[key] = strip
      if activeKeys[key.display] == key { relayout(key, animated: true) }
    }
    windows[id] = nil
    minimizedIDs.remove(id)
    draggedWindows.remove(id)
    parked.remove(id)
    lastTargets[id] = nil
    corrections[id] = nil
    manuallyFloating.remove(id)
    writer.forget(id)
    focusHistory.forget(id)
    if focusedID == id { focusedID = nil }
    scheduleDecorate()
  }

  private func removeFromHidden(_ id: WindowID) {
    for (key, var stack) in hidden where stack.contains(id) {
      stack.remove(id)
      hidden[key] = stack.isEmpty ? nil : stack
    }
  }

  private func removeFromStrips(_ id: WindowID) {
    removeFromHidden(id)
    for (key, var strip) in strips where strip.contains(id) {
      strip.remove(id)
      strips[key] = strip
      if activeKeys[key.display] == key { relayout(key, animated: true) }
    }
    lastTargets[id] = nil
    writer.invalidate(id)
  }

  private func forgetWrittenFrames() {
    writer.invalidateAll()
    lastTargets.removeAll()
  }

  private static func screenIsLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
  }

  private func scheduleRebuild(after delay: TimeInterval) {
    rebuildTimer?.invalidate()
    rebuildTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      self?.rebuild(resetOrder: false)
    }
  }

  private func scheduleWakeRebuilds() {
    scheduleRebuild(after: 1.0)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
      self?.scheduleRebuild(after: 0)
    }
  }

  private func rebuild(resetOrder: Bool) {
    guard isRunning, !Self.screenIsLocked() else { return }
    if staircase.reconcile(enabled: settings.isolateDisplays && !settings.spanDisplays) {
      forgetWrittenFrames()
      scheduleRebuild(after: 0.3)
      return
    }
    let restoring = pendingRestore
    pendingRestore = false
    let fresh = Display.current()
    if fresh != displays { forgetWrittenFrames() }
    displays = fresh
    activeKeys = [:]
    separateSpaces = !(UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false)
    let included = displays.filter { !settings.excludedDisplayIDs.contains($0.uuid) }
    if settings.spanDisplays, included.count > 1, Display.sideBySide(included) {
      let span = Display.spanning(included)
      let anchor = included.first(where: \.isPrimary) ?? included[0]
      let key = StripKey(display: span.uuid, space: Spaces.currentSpace(displayUUID: anchor.uuid))
      spanDisplay = span
      spanParts = included.sorted { $0.frame.minX < $1.frame.minX }
      activeKeys[span.uuid] = key
      included.forEach { activeKeys[$0.uuid] = key }
    } else {
      spanDisplay = nil
      spanParts = []
      for display in included {
        activeKeys[display.uuid] = StripKey(display: display.uuid, space: Spaces.currentSpace(displayUUID: display.uuid))
      }
    }

    for app in NSWorkspace.shared.runningApplications where Self.isManageable(app) && observers[app.processIdentifier] == nil {
      track(app, discover: false)
    }

    let liveDisplays = Set(activeKeys.keys)
    for key in hidden.keys where !liveDisplays.contains(key.display) { hidden[key] = nil }
    let hiddenIDs = Set(hidden.values.flatMap(\.windows))

    let onScreen = Spaces.onScreenWindowIDs()
    var found: [StripKey: [(ManagedWindow, CGRect)]] = [:]
    var unreadable: Set<pid_t> = []
    for (pid, observer) in observers {
      guard let elements = AX.readWindows(of: observer.app) else {
        unreadable.insert(pid)
        continue
      }
      for element in elements {
        let window = register(element, pid: pid)
        switch tileability(window) {
        case .tile:
          minimizedIDs.remove(window.id)
        case .minimized:
          minimizedIDs.insert(window.id)
          continue
        case .never, .notYet:
          continue
        }
        if hiddenIDs.contains(window.id) { continue }
        if let cgID = window.cgID, !onScreen.isEmpty, !onScreen.contains(cgID) { continue }
        guard let frame = AX.frame(element),
          let key = activeKey(containing: window.id) ?? display(containing: frame).flatMap({ activeKeys[$0.uuid] })
        else { continue }
        found[key, default: []].append((window, frame))
      }
    }

    let focusedID = focusedManagedWindow()?.id
    for key in Set(activeKeys.values) {
      guard let display = display(for: key) else { continue }
      let geometry = geometry(display)
      let entries = (found[key] ?? []).sorted { $0.1.minX < $1.1.minX }
      let ids = Set(entries.map(\.0.id))
      var strip = resetOrder ? Strip() : (strips[key] ?? Strip())
      if restoring, let saved = sessionStore.session.restore(
        display: key.display,
        live: entries.map { LiveWindow(id: $0.0.id, cgID: $0.0.cgID, bundleID: $0.0.bundleID) }
      ) {
        strip = saved.strip
        hidden[key] = saved.workspaces.isEmpty ? nil : saved.workspaces
      }
      let stashed = Set(hidden[key]?.windows ?? [])
      for id in strip.windows where stashed.contains(id) { strip.remove(id) }
      for id in strip.windows where !ids.contains(id) && !unreadable.contains(windows[id]?.pid ?? 0) { strip.remove(id) }
      for (window, frame) in entries where !strip.contains(window.id) && !stashed.contains(window.id) {
        for (otherKey, var other) in strips where otherKey != key && other.contains(window.id) {
          other.remove(window.id)
          strips[otherKey] = other
        }
        strip.append(window.id, width: columnWidth(frame, geometry))
        if window.isPrompt, let index = strip.columnIndex(of: window.id) {
          strip.columns[index].fixedHeight = frame.height
        }
      }
      if let focusedID, strip.contains(focusedID) { strip.focus(window: focusedID) }
      if let index = strip.focusedColumn {
        strip.scroll = revealScroll(strip, column: index, display)
      }
      strips[key] = strip
      relayout(key, animated: false)
      parkHidden(key)
    }
  }


  private func handle(_ event: WindowEvent, _ element: AXUIElement, pid: pid_t) {
    guard isRunning else { return }
    switch event {
    case .created:
      addWindow(element, pid: pid, attempt: 0)
    case .destroyed:
      if let window = lookup(element, pid: pid) { removeWindow(window.id) }
    case .focusChanged:
      syncFocus()
    case .moved, .resized:
      if let window = lookup(element, pid: pid) { frameChanged(window) }
    case .minimized:
      if let window = lookup(element, pid: pid) {
        removeFromStrips(window.id)
        minimizedIDs.insert(window.id)
        scheduleBarRefresh()
      }
    case .restored:
      if let window = lookup(element, pid: pid) { minimizedIDs.remove(window.id) }
      addWindow(element, pid: pid, attempt: 0)
    }
  }

  private func syncFocus() {
    scheduleBarRefresh()
    guard isRunning else { return }
    let window = focusedManagedWindow()
    if let id = window?.id { focusHistory.record(id) }
    focusedID = window?.id
    decorate(reorder: true)
    guard let window else { return }
    guard let key = activeKey(containing: window.id), var strip = strips[key], let display = display(for: key) else {
      if showHiddenWorkspace(containing: window.id) { return }
      if manuallyFloating.contains(window.id) == false, tileability(window) == .tile {
        addWindow(window.element, pid: window.pid, attempt: 0)
      }
      return
    }
    let changed = strip.focus(window: window.id)
    guard changed || Date().timeIntervalSince(lastManualScroll) > 0.6 else {
      strips[key] = strip
      return
    }
    if let index = strip.focusedColumn {
      strip.scroll = revealScroll(strip, column: index, display)
    }
    let moved = strip != strips[key]
    strips[key] = strip
    if moved { relayout(key, animated: true) }
  }

  private func frameChanged(_ window: ManagedWindow) {
    guard let key = activeKey(containing: window.id), lastTargets[window.id] != nil, !parked.contains(window.id) else { return }
    if NSEvent.pressedMouseButtons != 0 { draggedWindows.insert(window.id) }
    if animationTimer != nil || writer.isBusy(window.id, within: 0.35) || NSEvent.pressedMouseButtons != 0 {
      deferFrameCheck(window)
      return
    }
    let wasDragged = draggedWindows.remove(window.id) != nil
    guard var strip = strips[key], let display = display(for: key), let actual = AX.frame(window.element), let target = lastTargets[window.id] else {
      return
    }
    if AX.bool(window.element, "AXFullScreen") {
      removeFromStrips(window.id)
      return
    }
    let widthChanged = abs(actual.width - target.width) > 2
    let moved = abs(actual.minX - target.minX) > 2 || abs(actual.minY - target.minY) > 2 || abs(actual.height - target.height) > 2
    guard widthChanged || moved else { return }

    if moved, wasDragged, let landed = self.display(containing: actual), let landedKey = activeKeys[landed.uuid], landedKey != key {
      moveWindow(window.id, from: key, to: landedKey, width: columnWidth(actual, geometry(landed))) {
        $0.insertionIndex(forScreenX: actual.midX, $1)
      }
      return
    }

    if moved, wasDragged, !widthChanged, abs(actual.height - target.height) <= 2 {
      strip.drop(window.id, atScreenX: Self.quartzMouseLocation().x, geometry(display))
      if let index = strip.focusedColumn {
        strip.scroll = revealScroll(strip, column: index, display)
      }
      strips[key] = strip
      writer.invalidate(window.id)
      relayout(key, animated: true)
      return
    }

    let attempts = (corrections[window.id] ?? 0) + 1
    corrections[window.id] = attempts
    if attempts > 4 { return }

    if let index = strip.columnIndex(of: window.id) {
      if widthChanged {
        strip.columns[index].width = columnWidth(actual, geometry(display))
        strip.columns[index].widthBeforeFullWidth = nil
      }
      let column = strip.columns[index]
      if wasDragged, column.windows.count > 1, abs(actual.height - target.height) > 2, abs(actual.minX - target.minX) <= 2,
        let row = column.windows.firstIndex(of: window.id)
      {
        let gaps = Double(column.windows.count - 1) * settings.innerGap
        let available = geometry(display).usableHeight - gaps
        strip.columns[index].setShare(actual.height / available, row: row)
      }
      strips[key] = strip
    }
    writer.invalidate(window.id)
    relayout(key, animated: false)
  }

  private func moveWindow(
    _ id: WindowID,
    from sourceKey: StripKey,
    to targetKey: StripKey,
    width: Double,
    position: (Strip, StripGeometry) -> Int
  ) {
    guard var source = strips[sourceKey], let sourceDisplay = display(for: sourceKey), let targetDisplay = display(for: targetKey) else { return }
    let fixedHeight = source.columns.first { $0.windows.contains(id) }?.fixedHeight
    source.remove(id)
    if let index = source.focusedColumn {
      source.scroll = revealScroll(source, column: index, sourceDisplay)
    }
    strips[sourceKey] = source

    let targetGeometry = geometry(targetDisplay)
    var target = strips[targetKey] ?? Strip()
    target.insert(id, width: width, at: position(target, targetGeometry))
    if let column = target.columnIndex(of: id) { target.columns[column].fixedHeight = fixedHeight }
    if let index = target.focusedColumn {
      target.scroll = revealScroll(target, column: index, targetDisplay)
    }
    strips[targetKey] = target
    corrections[id] = nil
    writer.invalidate(id)
    relayout(sourceKey, animated: true)
    relayout(targetKey, animated: true)
    focus(id)
  }

  private func deferFrameCheck(_ window: ManagedWindow) {
    guard pendingFrameChecks.insert(window.id).inserted else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self else { return }
      self.pendingFrameChecks.remove(window.id)
      if let window = self.windows[window.id] { self.frameChanged(window) }
    }
  }


  private func wheel(_ delta: Double, at point: CGPoint) -> Bool {
    guard isRunning, let pointed = displays.first(where: { $0.contains(point) }), let key = activeKeys[pointed.uuid], var strip = strips[key],
      !strip.isEmpty, let display = display(for: key)
    else {
      return false
    }
    lastManualScroll = Date()
    var spring = springs[key] ?? Spring(position: strip.scroll)
    spring.setStiffness(900)
    let target = strip.clampedScroll(spring.target + delta, geometry(display))
    strip.scroll = target
    strips[key] = strip
    if settings.animate {
      spring.target = target
      springs[key] = spring
      startAnimating()
    } else {
      spring.jump(to: target)
      springs[key] = spring
      apply(key, scroll: target)
    }
    scheduleSettle(key, after: settings.thumbWheel.snapDelay, snap: settings.thumbWheel.snapToColumns)
    return true
  }

  private func swipe(_ phase: SwipePhase, at point: CGPoint) {
    guard isRunning, let display = displays.first(where: { $0.contains(point) }), let key = activeKeys[display.uuid], var strip = strips[key] else {
      return
    }
    lastManualScroll = Date()
    switch phase {
    case .began:
      snapTimers[key]?.invalidate()
      swiping.insert(key)
    case .changed(let fraction):
      guard let stripDisplay = self.display(for: key) else { return }
      let value = strip.clampedScroll(strip.scroll + fraction * display.visibleFrame.width, geometry(stripDisplay))
      strip.scroll = value
      strips[key] = strip
      var spring = springs[key] ?? Spring(position: value)
      spring.jump(to: value)
      springs[key] = spring
      apply(key, scroll: value)
    case .ended:
      swiping.remove(key)
      settle(key, snap: true)
    }
  }

  private func scheduleSettle(_ key: StripKey, after delay: TimeInterval, snap: Bool) {
    snapTimers[key]?.invalidate()
    snapTimers[key] = Timer.scheduledTimer(withTimeInterval: max(0.05, delay), repeats: false) { [weak self] _ in
      self?.settle(key, snap: snap)
    }
  }

  private func settle(_ key: StripKey, snap: Bool) {
    guard var strip = strips[key], let display = display(for: key) else { return }
    let geometry = geometry(display)
    if snap {
      strip.scroll = display.isSpan && separateSpaces
        ? strip.seamSafeSnapScroll(near: strip.scroll, seams: seams, keepVisible: nil, geometry)
        : strip.snapScroll(near: strip.scroll, geometry)
    }
    var focusTarget: WindowID?
    if let leftmost = strip.leftmostVisibleColumn(at: strip.scroll, geometry), leftmost != strip.focusedColumn {
      strip.focusedColumn = leftmost
      focusTarget = strip.focusedWindow
    }
    strips[key] = strip
    lastManualScroll = Date()
    relayout(key, animated: true, soft: true)
    if let focusTarget { focus(focusTarget) }
  }

  private func relayout(_ key: StripKey, animated: Bool, soft: Bool = false) {
    guard let strip = strips[key] else { return }
    scheduleBarRefresh()
    if animated && settings.animate, var spring = springs[key], abs(spring.position - strip.scroll) > 0.5 {
      spring.setStiffness(soft ? 220 : 900)
      spring.target = strip.scroll
      springs[key] = spring
      apply(key, scroll: spring.position)
      startAnimating()
    } else {
      springs[key] = Spring(position: strip.scroll)
      apply(key, scroll: strip.scroll)
    }
  }

  private func apply(_ key: StripKey, scroll: Double) {
    guard activeKeys[key.display] == key, let strip = strips[key], let display = display(for: key) else { return }
    for (id, placement) in strip.layout(context(display), scroll: scroll) {
      guard let window = windows[id] else { continue }
      if lastTargets[id] != placement.frame { corrections[id] = nil }
      if placement.isVisible {
        if parked.remove(id) != nil { writer.invalidate(id) }
      } else {
        parked.insert(id)
      }
      lastTargets[id] = placement.frame
      writer.submit(window.element, pid: window.pid, id: id, frame: placement.frame)
    }
    scheduleDecorate()
  }

  private func startAnimating() {
    guard animationTimer == nil else { return }
    lastTick = CACurrentMediaTime()
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(timer, forMode: .common)
    animationTimer = timer
  }

  private func tick() {
    let now = CACurrentMediaTime()
    let dt = min(1.0 / 30.0, now - lastTick)
    lastTick = now
    var moving = false
    for (key, var spring) in springs where !spring.isSettled && activeKeys[key.display] == key {
      spring.step(dt)
      springs[key] = spring
      if spring.isSettled {
        apply(key, scroll: spring.position)
      } else {
        apply(key, scroll: spring.position)
        moving = true
      }
    }
    if !moving {
      animationTimer?.invalidate()
      animationTimer = nil
    }
  }

  private func restoreAllWindows() {
    writer.cancelPending()
    let all = strips.map { ($0.key, $0.value) } + hidden.flatMap { key, stack in (stack.above + stack.below).map { (key, $0) } }
    for (key, strip) in all {
      let home = displays.first(where: { $0.uuid == key.display })
      for column in strip.columns {
        for (row, id) in column.windows.enumerated() {
          guard let window = windows[id], let current = AX.frame(window.element),
            let display = home ?? self.display(containing: current) ?? displays.first
          else { continue }
          let visible = display.visibleFrame
          let gap = settings.outerGap
          let geometry = StripGeometry(viewport: visible, innerGap: settings.innerGap, outerGap: gap)
          let width = min(geometry.points(forFraction: column.width), visible.width - 2 * gap)
          let slot = column.rows(top: visible.minY + gap, height: geometry.usableHeight, gap: settings.innerGap)[row]
          let height = column.fixedHeight.map { min($0, slot.height) } ?? slot.height
          let x = min(max(current.minX, visible.minX + gap), visible.maxX - gap - width)
          let y = slot.y
          AX.setPosition(window.element, CGPoint(x: x, y: y))
          AX.setSize(window.element, CGSize(width: width, height: height))
          AX.setPosition(window.element, CGPoint(x: x, y: y))
        }
      }
    }
  }

  private func focus(_ id: WindowID) {
    guard let window = windows[id] else { return }
    let generation = focusGeneration.next()
    let element = window.element
    let pid = window.pid
    focusQueue.async { [focusGeneration] in
      guard focusGeneration.isCurrent(generation) else { return }
      let app = AXUIElementCreateApplication(pid)
      AX.set(app, kAXFrontmostAttribute, true)
      AX.set(element, kAXMainAttribute, true)
      AXUIElementPerformAction(element, kAXRaiseAction as CFString)
      DispatchQueue.main.async {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
      }
    }
  }

  private func focusedElement(of pid: pid_t) -> AXUIElement? {
    let app = observers[pid]?.app ?? AXUIElementCreateApplication(pid)
    return AX.value(app, kAXFocusedWindowAttribute)
  }

  private func focusedManagedWindow() -> ManagedWindow? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, let element = focusedElement(of: pid) else {
      return nil
    }
    return lookup(element, pid: pid)
  }


  private func activeKey(containing id: WindowID) -> StripKey? {
    activeKeys.values.first { strips[$0]?.contains(id) == true }
  }

  private func display(for key: StripKey) -> Display? {
    if key.display == Display.spanID { return spanDisplay }
    return displays.first { $0.uuid == key.display }
  }

  private var seams: [Double] {
    spanParts.dropLast().map { Double($0.visibleFrame.maxX) }
  }

  private func revealScroll(_ strip: Strip, column index: Int, _ display: Display) -> Double {
    let geometry = geometry(display)
    let revealed = strip.revealScroll(column: index, mode: settings.centerMode, geometry)
    guard display.isSpan, separateSpaces else { return revealed }
    return strip.seamSafeSnapScroll(near: revealed, seams: seams, keepVisible: index, geometry)
  }

  private func band(_ display: Display) -> CGRect {
    var band = display.visibleFrame
    if settings.showBar && display.isPrimary { band.size.height -= BarMetrics.reserve }
    return band
  }

  private func display(containing frame: CGRect) -> Display? {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    if let display = displays.first(where: { $0.contains(center) }) { return display }
    return displays.min { $0.distance(to: center) < $1.distance(to: center) }
  }

  private func context(_ display: Display) -> LayoutContext {
    guard !display.isSpan else {
      return LayoutContext(geometry: geometry(display), displayFrame: display.frame, otherDisplays: [], bands: spanParts.map(band))
    }
    return LayoutContext(
      geometry: geometry(display),
      displayFrame: display.frame,
      otherDisplays: displays.filter { $0.id != display.id }.map { DisplayArea(frame: $0.frame) }
    )
  }

  private func geometry(_ display: Display) -> StripGeometry {
    var viewport = display.visibleFrame
    if settings.showBar && display.isPrimary { viewport.size.height -= BarMetrics.reserve }
    return StripGeometry(viewport: viewport, innerGap: settings.innerGap, outerGap: settings.outerGap)
  }

  private func scheduleDecorate() {
    guard !decorateQueued else { return }
    decorateQueued = true
    DispatchQueue.main.async { [weak self] in
      self?.decorateQueued = false
      self?.decorate(reorder: false)
    }
  }

  private func decorate(reorder: Bool) {
    let fullScreen = displays.contains { Spaces.isFullScreen(displayUUID: $0.uuid) }
    guard isRunning, !fullScreen, settings.focusBorder || settings.dimInactive else {
      decorations.hideAll()
      return
    }
    var focused: DecoratedWindow?
    var others: [DecoratedWindow] = []
    for key in Set(activeKeys.values) {
      for id in strips[key]?.windows ?? [] {
        guard let window = windows[id], let cgID = window.cgID, !parked.contains(id), let frame = lastTargets[id] else { continue }
        let radius = settings.cornerRadius > 0 ? settings.cornerRadius : window.cornerRadius
        let entry = DecoratedWindow(id: id, cgID: cgID, frame: frame, cornerRadius: CGFloat(radius))
        if id == focusedID { focused = entry } else { others.append(entry) }
      }
    }
    decorations.update(focused: focused, others: others, settings: settings, reorder: reorder)
  }

  private func showCheatsheet() {
    guard isRunning, settings.cheatsheetOnHold else { return }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    cheatsheet.show(Shortcut.cheatsheet(Shortcut.defaults), on: screen)
  }

  private func scheduleBarRefresh() {
    guard !barRefreshQueued else { return }
    barRefreshQueued = true
    DispatchQueue.main.async { [weak self] in
      self?.barRefreshQueued = false
      self?.refreshBars()
      self?.saveSession()
    }
  }

  private func saveSession() {
    guard isRunning || !strips.isEmpty else { return }
    var snapshot: [String: SessionStrip] = [:]
    var stacks: [String: SessionWorkspaces] = [:]
    let describe: (WindowID) -> SessionWindow? = { id in
      self.windows[id].map { SessionWindow(cgID: $0.cgID, bundleID: $0.bundleID) }
    }
    for key in Set(activeKeys.values) {
      guard let strip = strips[key] else { continue }
      snapshot[key.display] = SessionStrip(strip, describe: describe)
      let stack = hidden[key] ?? Workspaces()
      stacks[key.display] = SessionWorkspaces(
        above: stack.above.map { SessionStrip($0, describe: describe) },
        below: stack.below.map { SessionStrip($0, describe: describe) }
      )
    }
    sessionStore.update(snapshot, workspaces: stacks)
  }

  private func refreshBars() {
    guard isRunning, settings.showBar else {
      bars.hideAll()
      return
    }
    let focused = focusedManagedWindow()?.id
    let stripDisplays = spanDisplay.map { [$0] } ?? displays
      .filter { activeKeys[$0.uuid] != nil }
      .sorted { $0.frame.minX < $1.frame.minX }
    let groups = stripDisplays
      .map { display in
        let strip = activeKeys[display.uuid].flatMap { strips[$0] } ?? Strip()
        let tiles = strip.windows.compactMap { id in
          windows[id].map { BarTile(id: id, pid: $0.pid, focused: id == focused, minimized: false) }
        }
        let minimized = minimizedIDs.sorted().compactMap { id -> BarTile? in
          guard let window = windows[id], let frame = AX.frame(window.element),
            display.isSpan || self.display(containing: frame)?.uuid == display.uuid
          else { return nil }
          return BarTile(id: id, pid: window.pid, focused: false, minimized: true)
        }
        let closed = display.isPrimary || display.isSpan ? windowlessAppTiles(beside: tiles + minimized) : []
        return BarGroup(displayID: display.uuid, tiles: tiles + minimized + closed)
      }
    let primary = displays.first(where: \.isPrimary)
    guard let primary, !Spaces.isFullScreen(displayUUID: primary.uuid) else {
      bars.hideAll()
      return
    }
    bars.update(on: primary, groups: groups)
  }

  private func windowlessAppTiles(beside tiles: [BarTile]) -> [BarTile] {
    let shown = Set(tiles.map(\.pid))
    let tiled = Set(strips.values.flatMap(\.windows) + hidden.values.flatMap(\.windows) + minimizedIDs).compactMap { windows[$0]?.pid }
    for pid in tiled where !appsWithTiles.contains(pid) { appsWithTiles.append(pid) }
    let busy = Set(tiled)
    return appsWithTiles.compactMap { pid in
      guard !busy.contains(pid), !shown.contains(pid), let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
      return BarTile(id: Self.appTileBase | WindowID(UInt32(bitPattern: pid)), pid: pid, focused: false, minimized: true)
    }
  }

  private func reopenApp(_ id: WindowID) -> Bool {
    guard id & Self.appTileBase != 0 else { return false }
    let pid = pid_t(bitPattern: UInt32(truncatingIfNeeded: id))
    guard let app = NSRunningApplication(processIdentifier: pid) else { return true }
    if let url = app.bundleURL {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    } else {
      app.activate()
    }
    return true
  }

  private func reveal(_ id: WindowID) {
    if reopenApp(id) { return }
    if minimizedIDs.contains(id), let window = windows[id] {
      AX.set(window.element, kAXMinimizedAttribute, false)
      focus(id)
      return
    }
    if showHiddenWorkspace(containing: id) { return }
    guard let key = activeKey(containing: id), var strip = strips[key], let display = display(for: key) else { return }
    strip.focus(window: id)
    if let index = strip.focusedColumn {
      strip.scroll = revealScroll(strip, column: index, display)
    }
    strips[key] = strip
    relayout(key, animated: true)
    focus(id)
  }

  private func moveTile(_ id: WindowID, toDisplay displayID: String, index: Int) {
    guard let sourceKey = activeKey(containing: id), let targetKey = activeKeys[displayID], var strip = strips[sourceKey],
      let source = strip.columnIndex(of: id)
    else { return }
    guard sourceKey == targetKey else {
      moveWindow(id, from: sourceKey, to: targetKey, width: strip.columns[source].width) { _, _ in index }
      return
    }
    strip.moveColumn(from: source, to: min(index, strip.columns.count - 1))
    strips[sourceKey] = strip
    reveal(id)
  }

  private func label(for id: WindowID) -> String {
    if id & Self.appTileBase != 0 {
      let name = NSRunningApplication(processIdentifier: pid_t(bitPattern: UInt32(truncatingIfNeeded: id)))?.localizedName ?? ""
      return "\(name) · no windows"
    }
    guard let window = windows[id] else { return "" }
    let app = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? ""
    let title: String = AX.value(window.element, kAXTitleAttribute) ?? ""
    return title.isEmpty || title == app ? app : "\(app) · \(title)"
  }

  private static let systemPromptBundleIDs: Set<String> = [
    "com.apple.accessibility.universalAccessAuthWarn",
    "com.apple.SecurityAgent",
    "com.apple.UserNotificationCenter",
    "com.apple.CoreServicesUIAgent",
  ]

  static func isSystemPrompt(_ app: NSRunningApplication) -> Bool {
    if let id = app.bundleIdentifier, systemPromptBundleIDs.contains(id) { return true }
    return app.executableURL?.lastPathComponent == "universalAccessAuthWarn"
  }

  static func isManageable(_ app: NSRunningApplication) -> Bool {
    app.activationPolicy == .regular || isSystemPrompt(app)
  }

  static func quartzMouseLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
  }
}

final class Generation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }

  func isCurrent(_ candidate: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return value == candidate
  }
}
