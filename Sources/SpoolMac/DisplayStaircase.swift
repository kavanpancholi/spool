import AppKit
import OSLog
import SpoolCore

final class DisplayStaircase {
  private(set) var isApplied = false
  private let router = PointerRouter()
  private var desk: [UInt32: CGRect] = [:]
  private var applied: [UInt32: CGRect]?
  private var suspended = false
  private var activationToken: NSObjectProtocol?
  private var settingsWatch: Timer?
  private var onSuspendChange: (() -> Void)?
  private let log = Logger(subsystem: "io.github.kavanpancholi.spool", category: "displays")

  private static let systemSettings = "com.apple.systempreferences"

  func start(onSuspendChange: @escaping () -> Void) {
    self.onSuspendChange = onSuspendChange
    suspended = Self.displaysPaneOpen()
    watchSettings(NSWorkspace.shared.frontmostApplication)
    activationToken = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      self?.watchSettings(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }
    router.start()
  }

  func stop() {
    if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
    activationToken = nil
    settingsWatch?.invalidate()
    settingsWatch = nil
    onSuspendChange = nil
    restore()
    router.stop()
  }

  private func watchSettings(_ app: NSRunningApplication?) {
    settingsWatch?.invalidate()
    settingsWatch = nil
    if app?.bundleIdentifier == Self.systemSettings {
      settingsWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        self?.checkDisplaysPane()
      }
    }
    checkDisplaysPane()
  }

  private func checkDisplaysPane() {
    let open = Self.displaysPaneOpen()
    guard open != suspended else { return }
    suspended = open
    onSuspendChange?()
  }

  private static func displaysPaneOpen() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == systemSettings else { return false }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard let window: AXUIElement = AX.value(element, kAXFocusedWindowAttribute) else { return false }
    let title: String? = AX.value(window, kAXTitleAttribute)
    return title == displaysPaneTitle
  }

  private static let displaysPaneTitle: String = {
    let bundle = Bundle(path: "/System/Library/PreferencePanes/Displays.prefPane")
    return bundle?.localizedInfoDictionary?["CFBundleName"] as? String
      ?? bundle?.infoDictionary?["CFBundleName"] as? String
      ?? "Displays"
  }()

  func reconcile(enabled: Bool) -> Bool {
    let current = Self.currentFrames()
    let primary = CGMainDisplayID()
    guard current.count > 1, current[primary] != nil, !current.keys.contains(where: { CGDisplayIsInMirrorSet($0) != 0 }) else {
      forget(current)
      return false
    }
    if current != applied {
      desk = deskFor(current)
    }
    let wanted = enabled && !suspended ? DisplayArrangement.isolated(desk, primary: primary) : desk
    if wanted == current {
      applied = current
      isApplied = current != desk
      router.update(technical: current, desk: desk)
      return false
    }
    router.update(technical: [:], desk: [:])
    let result = Self.apply(wanted, scope: .forAppOnly)
    let observed = Self.currentFrames()
    guard result == .success, observed == wanted else {
      log.error("Display arrangement change failed: \(result.rawValue)")
      if observed != current { _ = Self.apply(current, scope: .forAppOnly) }
      forget(Self.currentFrames())
      return observed != current
    }
    applied = observed
    isApplied = observed != desk
    router.update(technical: observed, desk: desk)
    log.info("Display arrangement \(self.isApplied ? "isolated" : "restored")")
    return true
  }

  private func deskFor(_ current: [UInt32: CGRect]) -> [UInt32: CGRect] {
    guard isApplied, Set(current.keys) == Set(desk.keys), !DisplayArrangement.sharesRows(current),
      DisplayArrangement.sharesRows(desk)
    else { return current }
    return desk.reduce(into: [:]) { result, entry in
      result[entry.key] = CGRect(origin: entry.value.origin, size: current[entry.key]!.size)
    }
  }

  private func forget(_ current: [UInt32: CGRect]) {
    desk = current
    applied = current
    isApplied = false
    router.update(technical: [:], desk: [:])
  }

  private func restore() {
    router.update(technical: [:], desk: [:])
    defer {
      applied = nil
      isApplied = false
    }
    let current = Self.currentFrames()
    guard isApplied, current == applied, Set(current.keys) == Set(desk.keys), current != desk else { return }
    let result = Self.apply(desk, scope: .forSession)
    if result != .success { log.error("Display arrangement restore failed: \(result.rawValue)") }
  }

  private static func currentFrames() -> [UInt32: CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [:] }
    return Dictionary(uniqueKeysWithValues: ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) })
  }

  private static func apply(_ frames: [UInt32: CGRect], scope: CGConfigureOption) -> CGError {
    var config: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&config)
    guard begin == .success, let config else { return begin }
    for (id, frame) in frames.sorted(by: { $0.key < $1.key }) {
      let result = CGConfigureDisplayOrigin(config, id, Int32(frame.minX.rounded()), Int32(frame.minY.rounded()))
      guard result == .success else {
        CGCancelDisplayConfiguration(config)
        return result
      }
    }
    return CGCompleteDisplayConfiguration(config, scope)
  }
}

final class PointerRouter {
  private let lock = NSLock()
  private var technical: [UInt32: CGRect] = [:]
  private var desk: [UInt32: CGRect] = [:]
  private var thread: Thread?
  private var tap: CFMachPort?
  private var runLoop: CFRunLoop?
  private let source: CGEventSource? = {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.localEventsSuppressionInterval = 0
    return source
  }()

  func update(technical: [UInt32: CGRect], desk: [UInt32: CGRect]) {
    lock.lock()
    self.technical = technical
    self.desk = desk
    lock.unlock()
  }

  func start() {
    guard thread == nil else { return }
    let thread = Thread { [weak self] in self?.run() }
    thread.name = "Spool pointer"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
  }

  func stop() {
    lock.lock()
    let tap = self.tap
    let runLoop = self.runLoop
    self.tap = nil
    self.runLoop = nil
    lock.unlock()
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let runLoop { CFRunLoopStop(runLoop) }
    thread = nil
  }

  private func run() {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let router = Unmanaged<PointerRouter>.fromOpaque(refcon).takeUnretainedValue()
      router.handle(type, event)
      return Unmanaged.passUnretained(event)
    }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else { return }
    let loop = CFRunLoopGetCurrent()
    lock.lock()
    self.tap = tap
    runLoop = loop
    lock.unlock()
    CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    CFRunLoopRun()
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) {
    lock.lock()
    defer { lock.unlock() }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return
    }
    guard let point = DisplayArrangement.pointerDestination(
      at: event.location,
      delta: CGVector(
        dx: event.getDoubleValueField(.mouseEventDeltaX),
        dy: event.getDoubleValueField(.mouseEventDeltaY)
      ),
      technical: technical,
      desk: desk
    ) else { return }
    withExtendedLifetime(source) {
      guard CGWarpMouseCursorPosition(point) == .success else { return }
      CGAssociateMouseAndMouseCursorPosition(1)
      event.location = point
    }
  }
}
