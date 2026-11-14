import AppKit
import SpoolCore

public struct Display: Equatable {
  public let id: CGDirectDisplayID
  public let uuid: String
  public let name: String
  public let frame: CGRect
  public let visibleFrame: CGRect
  public let cocoaVisibleFrame: CGRect
  public let scale: CGFloat

  public static func current() -> [Display] {
    guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
    return NSScreen.screens.compactMap { screen -> Display? in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
      let id = CGDirectDisplayID(number.uint32Value)
      let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "\(id)"
      return Display(
        id: id,
        uuid: uuid,
        name: screen.localizedName,
        frame: quartz(screen.frame, primaryHeight: primaryHeight),
        visibleFrame: quartz(screen.visibleFrame, primaryHeight: primaryHeight),
        cocoaVisibleFrame: screen.visibleFrame,
        scale: screen.backingScaleFactor
      )
    }
  }

  public static let spanID = "span"

  public var isSpan: Bool { uuid == Display.spanID }
  public var isPrimary: Bool { !isSpan && frame.origin == .zero }

  static func spanning(_ parts: [Display]) -> Display {
    let frame = parts.dropFirst().reduce(parts[0].frame) { $0.union($1.frame) }
    let visible = parts.dropFirst().reduce(parts[0].visibleFrame) { $0.union($1.visibleFrame) }
    return Display(
      id: 0,
      uuid: spanID,
      name: "All displays",
      frame: frame,
      visibleFrame: visible,
      cocoaVisibleFrame: .zero,
      scale: parts.map(\.scale).max() ?? 2
    )
  }

  static func sideBySide(_ displays: [Display]) -> Bool {
    let sorted = displays.sorted { $0.frame.minX < $1.frame.minX }
    return zip(sorted, sorted.dropFirst()).allSatisfy { left, right in
      abs(left.frame.maxX - right.frame.minX) < 2
        && min(left.frame.maxY, right.frame.maxY) - max(left.frame.minY, right.frame.minY) > 0
    }
  }

  public func contains(_ point: CGPoint) -> Bool {
    frame.contains(point)
  }

  func distance(to point: CGPoint) -> Double {
    let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
    let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
    return dx * dx + dy * dy
  }

  private static func quartz(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }
}
