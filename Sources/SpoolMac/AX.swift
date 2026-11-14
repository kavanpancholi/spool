import AppKit
import ApplicationServices
import SpoolCore

enum AX {
  static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
    return raw as? T
  }

  static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
    (value(element, attribute) as NSNumber?)?.boolValue ?? false
  }

  static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
    return settable.boolValue
  }

  static func frame(_ element: AXUIElement) -> CGRect? {
    guard let positionValue: AXValue = axValue(element, kAXPositionAttribute),
      let sizeValue: AXValue = axValue(element, kAXSizeAttribute)
    else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue, .cgPoint, &point)
    AXValueGetValue(sizeValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
  }

  @discardableResult
  static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
    var point = point
    guard let value = AXValueCreate(.cgPoint, &point) else { return false }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
  }

  @discardableResult
  static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
  }

  static func set(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
    AXUIElementSetAttributeValue(element, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
  }

  static func windows(of app: AXUIElement) -> [AXUIElement] {
    value(app, kAXWindowsAttribute) ?? []
  }

  static func pid(of element: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
  }

  static func cgWindowID(_ element: AXUIElement) -> CGWindowID? {
    guard let getWindow = getWindowFunction else { return nil }
    var id: CGWindowID = 0
    return getWindow(element, &id) == .success && id != 0 ? id : nil
  }

  private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let raw, CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    return (raw as! AXValue)
  }

  private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

  private static let getWindowFunction: GetWindowFunction? = {
    guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
      let symbol = dlsym(handle, "_AXUIElementGetWindow")
    else { return nil }
    return unsafeBitCast(symbol, to: GetWindowFunction.self)
  }()
}

enum Spaces {
  private typealias MainConnection = @convention(c) () -> Int32
  private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64

  private static let functions: (MainConnection, CurrentSpace)? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
      let connection = dlsym(handle, "CGSMainConnectionID"),
      let current = dlsym(handle, "CGSManagedDisplayGetCurrentSpace")
    else { return nil }
    return (unsafeBitCast(connection, to: MainConnection.self), unsafeBitCast(current, to: CurrentSpace.self))
  }()

  static func currentSpace(displayUUID: String) -> UInt64 {
    guard let (connection, current) = functions else { return 0 }
    let id = current(connection(), displayUUID as CFString)
    if id != 0 { return id }
    return current(connection(), "Main" as CFString)
  }

  static func onScreenWindowIDs() -> Set<CGWindowID> {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
      return []
    }
    return Set(info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
  }
}
