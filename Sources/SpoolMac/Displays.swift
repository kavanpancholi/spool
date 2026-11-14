import AppKit
import SpoolCore

public struct Display: Equatable {
  public let id: CGDirectDisplayID
  public let uuid: String
  public let name: String
  public let frame: CGRect
  public let visibleFrame: CGRect
  public var neighbourEdges: Edges = []

  public static func current() -> [Display] {
    guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
    var displays = NSScreen.screens.compactMap { screen -> Display? in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
      let id = CGDirectDisplayID(number.uint32Value)
      let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "\(id)"
      return Display(
        id: id,
        uuid: uuid,
        name: screen.localizedName,
        frame: quartz(screen.frame, primaryHeight: primaryHeight),
        visibleFrame: quartz(screen.visibleFrame, primaryHeight: primaryHeight)
      )
    }
    for index in displays.indices {
      displays[index].neighbourEdges = neighbours(of: displays[index], among: displays)
    }
    return displays
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

  private static func neighbours(of display: Display, among all: [Display]) -> Edges {
    var edges: Edges = []
    let a = display.frame
    for other in all where other.id != display.id {
      let b = other.frame
      let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0
      let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0
      if verticalOverlap && abs(b.maxX - a.minX) < 2 { edges.insert(.left) }
      if verticalOverlap && abs(b.minX - a.maxX) < 2 { edges.insert(.right) }
      if horizontalOverlap && abs(b.maxY - a.minY) < 2 { edges.insert(.top) }
      if horizontalOverlap && abs(b.minY - a.maxY) < 2 { edges.insert(.bottom) }
    }
    return edges
  }
}
