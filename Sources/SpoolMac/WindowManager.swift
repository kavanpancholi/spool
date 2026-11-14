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

  init(id: WindowID, element: AXUIElement, pid: pid_t, bundleID: String?, cgID: CGWindowID?) {
    self.id = id
    self.element = element
    self.pid = pid
    self.bundleID = bundleID
    self.cgID = cgID
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
  private let focusQueue = DispatchQueue(label: "Spool focus", qos: .userInteractive)
  private let focusGeneration = Generation()

  private var observers: [pid_t: AppObserver] = [:]
  private var windows: [WindowID: ManagedWindow] = [:]
  private var nextID: WindowID = 1
  private var displays: [Display] = []
  private var activeKeys: [String: StripKey] = [:]
  private var strips: [StripKey: Strip] = [:]
  private var springs: [StripKey: Spring] = [:]
  private var lastTargets: [WindowID: CGRect] = [:]
  private var manuallyFloating: Set<WindowID> = []
  private var corrections: [WindowID: Int] = [:]
  private var parked: Set<WindowID> = []
  private var pendingFrameChecks: Set<WindowID> = []

  private var animationTimer: Timer?
  private var lastTick = CACurrentMediaTime()
  private var snapTimers: [StripKey: Timer] = [:]
  private var rebuildTimer: Timer?
  private var lastManualScroll = Date.distantPast
  private var workspaceTokens: [(NotificationCenter, NSObjectProtocol)] = []
  private var cancellables: Set<AnyCancellable> = []

  public init(store: SettingsStore) {
    self.store = store
    hotKeys.onCommand = { [weak self] command in self?.perform(command) }
    failedShortcuts = hotKeys.register(Shortcut.defaults)
    input.onWheel = { [weak self] delta, point in self?.wheel(delta, at: point) ?? false }
    input.onSwipe = { [weak self] phase, point in self?.swipe(phase, at: point) }
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
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      track(app, discover: false)
    }
    rebuild(resetOrder: true)
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
    for (center, token) in workspaceTokens { center.removeObserver(token) }
    workspaceTokens.removeAll()
    unparkAll()
    observers.removeAll()
    windows.values.forEach { writer.forget($0.id) }
    windows.removeAll()
    strips.removeAll()
    springs.removeAll()
    activeKeys.removeAll()
    lastTargets.removeAll()
    parked.removeAll()
    corrections.removeAll()
    manuallyFloating.removeAll()
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
    rebuild(resetOrder: false)
  }


  public func perform(_ command: Command) {
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
    default:
      let result = strip.apply(command, settings: settings, geometry: geometry(display))
      guard result.handled else { return }
      strips[key] = strip
      if result.layoutChanged { relayout(key, animated: true) }
      if result.focusChanged, let id = strip.focusedWindow { focus(id) }
    }
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
      destination.scroll = destination.revealScroll(column: index, mode: settings.centerMode, geometry(target))
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
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.activationPolicy == .regular
      else { return }
      self?.track(app, discover: true)
    }
    on(center, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
      self?.forget(pid: app.processIdentifier)
    }
    on(center, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
      self?.syncFocus()
    }
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
      on(center, name) { [weak self] _ in self?.scheduleRebuild(after: 0.25) }
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      on(center, name) { [weak self] _ in self?.scheduleRebuild(after: 1.0) }
    }
    on(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
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
    let gone = windows.values.filter { $0.pid == pid }.map(\.id)
    gone.forEach { removeWindow($0) }
  }

  private func register(_ element: AXUIElement, pid: pid_t) -> ManagedWindow {
    if let existing = lookup(element, pid: pid) { return existing }
    let window = ManagedWindow(
      id: nextID,
      element: element,
      pid: pid,
      bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
      cgID: AX.cgWindowID(element)
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

  private enum Tileability { case tile, never, notYet }

  private func tileability(_ window: ManagedWindow) -> Tileability {
    if manuallyFloating.contains(window.id) { return .never }
    if let bundleID = window.bundleID, settings.floatingBundleIDs.contains(bundleID) { return .never }
    let element = window.element
    guard let role: String = AX.value(element, kAXRoleAttribute), let subrole: String = AX.value(element, kAXSubroleAttribute) else {
      return .notYet
    }
    guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole else { return .never }
    if AX.bool(element, kAXMinimizedAttribute) || AX.bool(element, "AXFullScreen") { return .never }
    guard AX.isSettable(element, kAXSizeAttribute), AX.isSettable(element, kAXPositionAttribute) else { return .never }
    guard let frame = AX.frame(element) else { return .notYet }
    guard frame.width >= 80, frame.height >= 60 else { return .never }
    return .tile
  }

  private func addWindow(_ element: AXUIElement, pid: pid_t, attempt: Int) {
    guard isRunning else { return }
    let window = register(element, pid: pid)

    switch tileability(window) {
    case .never:
      return
    case .notYet:
      if attempt < 3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + [0.1, 0.3, 0.8][attempt]) { [weak self] in
          self?.addWindow(element, pid: pid, attempt: attempt + 1)
        }
      }
      return
    case .tile:
      break
    }

    if let cgID = window.cgID, !Spaces.onScreenWindowIDs().contains(cgID) {
      if attempt < 3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + [0.1, 0.3, 0.8][attempt]) { [weak self] in
          self?.addWindow(element, pid: pid, attempt: attempt + 1)
        }
      }
      return
    }
    guard activeKey(containing: window.id) == nil,
      let frame = AX.frame(element),
      let display = display(containing: frame),
      let key = activeKeys[display.uuid]
    else { return }

    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    let focused = frontmost && focusedElement(of: pid).map { CFEqual($0, element) } == true
    var strip = strips[key] ?? Strip()
    let geometry = geometry(display)
    strip.insert(window.id, width: min(1, max(0.1, geometry.fraction(forPoints: frame.width))), focus: focused)
    if focused, let index = strip.focusedColumn {
      strip.scroll = strip.revealScroll(column: index, mode: settings.centerMode, geometry)
    }
    strips[key] = strip
    relayout(key, animated: true)
  }

  private func removeWindow(_ id: WindowID) {
    for (key, var strip) in strips where strip.contains(id) {
      strip.remove(id)
      if let index = strip.focusedColumn, let display = display(for: key) {
        strip.scroll = strip.revealScroll(column: index, mode: settings.centerMode, geometry(display))
      }
      strips[key] = strip
      if activeKeys[key.display] == key { relayout(key, animated: true) }
    }
    windows[id] = nil
    parked.remove(id)
    lastTargets[id] = nil
    corrections[id] = nil
    manuallyFloating.remove(id)
    writer.forget(id)
  }

  private func removeFromStrips(_ id: WindowID) {
    for (key, var strip) in strips where strip.contains(id) {
      strip.remove(id)
      strips[key] = strip
      if activeKeys[key.display] == key { relayout(key, animated: true) }
    }
    lastTargets[id] = nil
    writer.invalidate(id)
  }

  private func scheduleRebuild(after delay: TimeInterval) {
    rebuildTimer?.invalidate()
    rebuildTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      self?.rebuild(resetOrder: false)
    }
  }

  private func rebuild(resetOrder: Bool) {
    guard isRunning else { return }
    displays = Display.current()
    activeKeys = [:]
    for display in displays where !settings.excludedDisplayIDs.contains(display.uuid) {
      activeKeys[display.uuid] = StripKey(display: display.uuid, space: Spaces.currentSpace(displayUUID: display.uuid))
    }

    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && observers[app.processIdentifier] == nil {
      track(app, discover: false)
    }

    let onScreen = Spaces.onScreenWindowIDs()
    var found: [StripKey: [(ManagedWindow, CGRect)]] = [:]
    for (pid, observer) in observers {
      for element in AX.windows(of: observer.app) {
        let window = register(element, pid: pid)
        guard tileability(window) == .tile else { continue }
        if let cgID = window.cgID, !onScreen.isEmpty, !onScreen.contains(cgID) { continue }
        guard let frame = AX.frame(element), let display = display(containing: frame), let key = activeKeys[display.uuid] else { continue }
        found[key, default: []].append((window, frame))
      }
    }

    let focusedID = focusedManagedWindow()?.id
    for display in displays {
      guard let key = activeKeys[display.uuid] else { continue }
      let geometry = geometry(display)
      let entries = (found[key] ?? []).sorted { $0.1.minX < $1.1.minX }
      let ids = Set(entries.map(\.0.id))
      var strip = resetOrder ? Strip() : (strips[key] ?? Strip())
      for id in strip.windows where !ids.contains(id) { strip.remove(id) }
      for (window, frame) in entries where !strip.contains(window.id) {
        for (otherKey, var other) in strips where otherKey != key && other.contains(window.id) {
          other.remove(window.id)
          strips[otherKey] = other
        }
        strip.append(window.id, width: min(1, max(0.1, geometry.fraction(forPoints: frame.width))))
      }
      if let focusedID, strip.contains(focusedID) { strip.focus(window: focusedID) }
      if let index = strip.focusedColumn {
        strip.scroll = strip.revealScroll(column: index, mode: settings.centerMode, geometry)
      }
      strips[key] = strip
      relayout(key, animated: false)
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
      if let window = lookup(element, pid: pid) { removeFromStrips(window.id) }
    case .restored:
      addWindow(element, pid: pid, attempt: 0)
    }
  }

  private func syncFocus() {
    guard isRunning, let window = focusedManagedWindow() else { return }
    guard let key = activeKey(containing: window.id), var strip = strips[key], let display = display(for: key) else {
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
      strip.scroll = strip.revealScroll(column: index, mode: settings.centerMode, geometry(display))
    }
    let moved = strip != strips[key]
    strips[key] = strip
    if moved { relayout(key, animated: true) }
  }

  private func frameChanged(_ window: ManagedWindow) {
    guard let key = activeKey(containing: window.id), lastTargets[window.id] != nil, !parked.contains(window.id) else { return }
    if animationTimer != nil || writer.isBusy(window.id, within: 0.35) || NSEvent.pressedMouseButtons != 0 {
      deferFrameCheck(window)
      return
    }
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

    let attempts = (corrections[window.id] ?? 0) + 1
    corrections[window.id] = attempts
    if attempts > 4 { return }

    if widthChanged, let index = strip.columnIndex(of: window.id) {
      strip.columns[index].width = min(1, max(0.1, geometry(display).fraction(forPoints: actual.width)))
      strip.columns[index].widthBeforeFullWidth = nil
      strips[key] = strip
    }
    writer.invalidate(window.id)
    relayout(key, animated: false)
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
    guard isRunning, let display = displays.first(where: { $0.contains(point) }), let key = activeKeys[display.uuid], var strip = strips[key],
      !strip.isEmpty
    else {
      return false
    }
    lastManualScroll = Date()
    var spring = springs[key] ?? Spring(position: strip.scroll)
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
    case .changed(let fraction):
      let value = strip.clampedScroll(strip.scroll + fraction * display.visibleFrame.width, geometry(display))
      strip.scroll = value
      strips[key] = strip
      var spring = springs[key] ?? Spring(position: value)
      spring.jump(to: value)
      springs[key] = spring
      apply(key, scroll: value)
    case .ended:
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
    if snap { strip.scroll = strip.snapScroll(near: strip.scroll, geometry) }
    var focusTarget: WindowID?
    if let focused = strip.focusedColumn, !strip.fullyVisibleColumns(at: strip.scroll, geometry).contains(focused),
      let nearest = strip.columnNearestCenter(at: strip.scroll, geometry)
    {
      strip.focusedColumn = nearest
      focusTarget = strip.focusedWindow
    }
    strips[key] = strip
    lastManualScroll = Date()
    relayout(key, animated: true)
    if let focusTarget { focus(focusTarget) }
  }


  private func relayout(_ key: StripKey, animated: Bool) {
    guard let strip = strips[key] else { return }
    if animated && settings.animate, var spring = springs[key] {
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
    let context = LayoutContext(geometry: geometry(display), displayFrame: display.frame, neighbourEdges: display.neighbourEdges)
    for (id, placement) in strip.layout(context, scroll: scroll) {
      guard let window = windows[id] else { continue }
      if lastTargets[id] != placement.frame { corrections[id] = nil }
      if placement.isVisible { parked.remove(id) } else { parked.insert(id) }
      lastTargets[id] = placement.frame
      writer.submit(window.element, pid: window.pid, id: id, frame: placement.frame)
    }
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
      apply(key, scroll: spring.position)
      moving = true
    }
    if !moving {
      animationTimer?.invalidate()
      animationTimer = nil
    }
  }

  private func unparkAll() {
    for (uuid, key) in activeKeys {
      guard let strip = strips[key], let display = displays.first(where: { $0.uuid == uuid }) else { continue }
      let visible = display.visibleFrame
      let context = LayoutContext(geometry: geometry(display), displayFrame: display.frame, neighbourEdges: display.neighbourEdges)
      for (id, placement) in strip.layout(context) {
        guard case .parked(let frame) = placement, let window = windows[id] else { continue }
        let width = min(frame.width, visible.width)
        let x = frame.midX < visible.midX ? visible.minX + settings.outerGap : visible.maxX - width - settings.outerGap
        AX.setPosition(window.element, CGPoint(x: max(visible.minX, x), y: max(visible.minY, frame.minY)))
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
    displays.first { $0.uuid == key.display }
  }

  private func display(containing frame: CGRect) -> Display? {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    if let display = displays.first(where: { $0.contains(center) }) { return display }
    return displays.min { $0.distance(to: center) < $1.distance(to: center) }
  }

  private func geometry(_ display: Display) -> StripGeometry {
    StripGeometry(viewport: display.visibleFrame, innerGap: settings.innerGap, outerGap: settings.outerGap)
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
