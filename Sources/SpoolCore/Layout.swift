import CoreGraphics
import Foundation

public enum Placement: Equatable, Sendable {
  case visible(CGRect)
  case parked(CGRect)

  public var frame: CGRect {
    switch self {
    case .visible(let frame), .parked(let frame): frame
    }
  }

  public var isVisible: Bool {
    if case .parked = self { return false }
    return true
  }
}

public struct DisplayArea: Equatable, Sendable {
  public var frame: CGRect

  public init(frame: CGRect) {
    self.frame = frame
  }
}

public struct LayoutContext: Equatable, Sendable {
  public var geometry: StripGeometry
  public var displayFrame: CGRect
  public var otherDisplays: [DisplayArea]
  public var bands: [CGRect]

  public init(geometry: StripGeometry, displayFrame: CGRect, otherDisplays: [DisplayArea], bands: [CGRect] = []) {
    self.geometry = geometry
    self.displayFrame = displayFrame
    self.otherDisplays = otherDisplays
    self.bands = bands
  }

  func verticalSpace(forColumnCenter x: Double) -> (top: Double, height: Double) {
    let gap = geometry.outerGap
    guard let band = bands.first(where: { x >= $0.minX && x < $0.maxX })
      ?? bands.min(by: { abs($0.midX - x) < abs($1.midX - x) })
    else {
      return (geometry.viewport.minY + gap, geometry.usableHeight)
    }
    return (band.minY + gap, max(1, band.height - 2 * gap))
  }

  static let titleBarKeptOnScreen = 60.0

  func isMostlyOnOtherDisplay(_ rect: CGRect) -> Bool {
    let own = rect.intersection(displayFrame).area
    return otherDisplays.contains { rect.intersection($0.frame).area > own }
  }

  func touchesOtherDisplay(_ rect: CGRect) -> Bool {
    var reach = rect
    let clampedTop = min(rect.minY, displayFrame.maxY - Self.titleBarKeptOnScreen)
    reach.size.height += rect.minY - clampedTop
    reach.origin.y = clampedTop
    return otherDisplays.contains { reach.intersection($0.frame).area > 0 }
  }
}

extension CGRect {
  var area: Double { isNull || isEmpty ? 0 : Double(width * height) }
}

extension Strip {
  public func layout(_ context: LayoutContext, scroll: Double? = nil) -> [WindowID: Placement] {
    let geometry = context.geometry
    let viewport = geometry.viewport
    let offset = scroll ?? self.scroll
    let lefts = columnLefts(geometry)
    var result: [WindowID: Placement] = [:]

    for (index, column) in columns.enumerated() {
      let width = geometry.points(forFraction: column.width).rounded()
      let x = (viewport.minX + lefts[index] - offset).rounded()
      let space = context.verticalSpace(forColumnCenter: x + width / 2)
      let rows = column.rows(top: space.top, height: space.height, gap: geometry.innerGap)
      let columnRect = CGRect(x: x, y: space.top, width: width, height: space.height)
      let park = x + width <= viewport.minX || x >= viewport.maxX || context.isMostlyOnOtherDisplay(columnRect)

      for (row, window) in column.windows.enumerated() {
        var y = rows[row].y
        var height = rows[row].height
        let rowHeight = height
        if let fixed = column.fixedHeight, fixed < rowHeight {
          y += ((rowHeight - fixed) / 2).rounded()
          height = fixed
        }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        if park {
          result[window] = .parked(parkedFrame(for: frame, preferLeft: x + width / 2 < viewport.midX, context))
        } else {
          result[window] = .visible(frame)
        }
      }
    }
    return result
  }

  private func parkedFrame(for frame: CGRect, preferLeft: Bool, _ context: LayoutContext) -> CGRect {
    let display = context.displayFrame
    let leftX = display.minX - frame.width + 1
    let rightX = display.maxX - 1
    let (nearX, farX) = preferLeft ? (leftX, rightX) : (rightX, leftX)
    let bottomY = display.maxY - 1

    let candidates = [
      CGPoint(x: nearX, y: bottomY),
      CGPoint(x: farX, y: bottomY),
      CGPoint(x: nearX, y: frame.minY),
      CGPoint(x: farX, y: frame.minY),
    ]
    let origin = candidates.first { !context.touchesOtherDisplay(CGRect(origin: $0, size: frame.size)) } ?? candidates[0]
    return CGRect(origin: origin, size: frame.size)
  }
}
