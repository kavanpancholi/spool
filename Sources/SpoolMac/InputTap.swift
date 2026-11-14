import AppKit
import SpoolCore

enum SwipePhase {
  case began
  case changed(Double)
  case ended
}

final class InputTap {
  var thumbWheel = ThumbWheelSettings()
  var trackpad = TrackpadSettings()
  var onWheel: ((Double, CGPoint) -> Bool)?
  var onSwipe: ((SwipePhase, CGPoint) -> Void)?

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var swipeAnchor: Double?
  private var swiping = false

  private static let gestureEventType = CGEventType(rawValue: 29)!

  var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

  func start() -> Bool {
    guard tap == nil else { return true }
    let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue) | (CGEventMask(1) << Self.gestureEventType.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let input = Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue()
      return input.handle(type, event)
    }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else { return false }
    self.tap = tap
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    swipeAnchor = nil
    swiping = false
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    case .scrollWheel:
      return handleScroll(event) ? nil : Unmanaged.passUnretained(event)
    case Self.gestureEventType:
      return handleGesture(event) ? nil : Unmanaged.passUnretained(event)
    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func handleScroll(_ event: CGEvent) -> Bool {
    let sample = ScrollSample(
      pointDeltaX: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
      pointDeltaY: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
      lineDeltaX: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
      lineDeltaY: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
      scrollPhase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
      momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
      modifiers: Self.modifiers(event.flags),
      bundleIDUnderPointer: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    )
    guard case .scrollStrip(let delta) = ScrollClassifier.route(sample, settings: thumbWheel), let onWheel else {
      return false
    }
    return onWheel(delta, event.location)
  }

  private func handleGesture(_ event: CGEvent) -> Bool {
    let fingers = trackpad.fingers
    guard fingers >= 3, let onSwipe, let nsEvent = NSEvent(cgEvent: event) else { return false }
    let touches = nsEvent.allTouches().filter { $0.phase != .ended && $0.phase != .cancelled }
    let location = event.location

    guard touches.count == fingers else {
      if swiping {
        swiping = false
        swipeAnchor = nil
        onSwipe(.ended, location)
        return true
      }
      swipeAnchor = nil
      return false
    }

    let averageX = touches.reduce(0.0) { $0 + Double($1.normalizedPosition.x) } / Double(touches.count)
    guard let anchor = swipeAnchor else {
      swipeAnchor = averageX
      return false
    }
    let travel = averageX - anchor
    if !swiping {
      guard abs(travel) > 0.015 else { return false }
      swiping = true
      onSwipe(.began, location)
    }
    swipeAnchor = averageX
    let direction = trackpad.inverted ? 1.0 : -1.0
    onSwipe(.changed(travel * direction * trackpad.speed), location)
    return true
  }

  static func modifiers(_ flags: CGEventFlags) -> ModifierState {
    var state: ModifierState = []
    if flags.contains(.maskShift) { state.insert(.shift) }
    if flags.contains(.maskControl) { state.insert(.control) }
    if flags.contains(.maskAlternate) { state.insert(.option) }
    if flags.contains(.maskCommand) { state.insert(.command) }
    return state
  }
}
