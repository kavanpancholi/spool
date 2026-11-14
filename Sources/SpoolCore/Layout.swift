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
    if case .visible = self { return true }
    return false
  }
}

public struct LayoutContext: Equatable, Sendable {
  public var geometry: StripGeometry
  public var displayFrame: CGRect
  public var otherDisplays: [CGRect]

  public init(geometry: StripGeometry, displayFrame: CGRect, otherDisplays: [CGRect]) {
    self.geometry = geometry
    self.displayFrame = displayFrame
    self.otherDisplays = otherDisplays
  }

  static let titleBarKeptOnScreen = 60.0

  func isMostlyOnOtherDisplay(_ rect: CGRect) -> Bool {
    let own = rect.intersection(displayFrame).area
    return otherDisplays.contains { rect.intersection($0).area > own }
  }

  func touchesOtherDisplay(_ rect: CGRect) -> Bool {
    var reach = rect
    let clampedTop = min(rect.minY, displayFrame.maxY - Self.titleBarKeptOnScreen)
    reach.size.height += rect.minY - clampedTop
    reach.origin.y = clampedTop
    return otherDisplays.contains { reach.intersection($0).area > 0 }
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
      let count = Double(column.windows.count)
      let rowHeight = ((geometry.usableHeight - (count - 1) * geometry.innerGap) / count).rounded(.down)
      let columnRect = CGRect(x: x, y: viewport.minY + geometry.outerGap, width: width, height: geometry.usableHeight)
      let park = x + width <= viewport.minX || x >= viewport.maxX || context.isMostlyOnOtherDisplay(columnRect)

      for (row, window) in column.windows.enumerated() {
        let y = (viewport.minY + geometry.outerGap + Double(row) * (rowHeight + geometry.innerGap)).rounded()
        let frame = CGRect(x: x, y: y, width: width, height: rowHeight)
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
