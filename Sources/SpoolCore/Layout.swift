import CoreGraphics
import Foundation

public struct Edges: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let left = Edges(rawValue: 1 << 0)
  public static let right = Edges(rawValue: 1 << 1)
  public static let top = Edges(rawValue: 1 << 2)
  public static let bottom = Edges(rawValue: 1 << 3)
}

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
  public var neighbourEdges: Edges

  public init(geometry: StripGeometry, displayFrame: CGRect, neighbourEdges: Edges) {
    self.geometry = geometry
    self.displayFrame = displayFrame
    self.neighbourEdges = neighbourEdges
  }
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

      let entirelyOutside = x + width <= viewport.minX || x >= viewport.maxX
      let crossesBlockedLeft = x < viewport.minX - 0.5 && context.neighbourEdges.contains(.left)
      let crossesBlockedRight = x + width > viewport.maxX + 0.5 && context.neighbourEdges.contains(.right)
      let park = entirelyOutside || crossesBlockedLeft || crossesBlockedRight

      for (row, window) in column.windows.enumerated() {
        let y = (viewport.minY + geometry.outerGap + Double(row) * (rowHeight + geometry.innerGap)).rounded()
        let frame = CGRect(x: x, y: y, width: width, height: rowHeight)
        if park {
          let preferLeft = x + width / 2 < viewport.midX
          result[window] = .parked(parkedFrame(for: frame, preferLeft: preferLeft, context))
        } else {
          result[window] = .visible(frame)
        }
      }
    }
    return result
  }

  private func parkedFrame(for frame: CGRect, preferLeft: Bool, _ context: LayoutContext) -> CGRect {
    let display = context.displayFrame
    let blocked = context.neighbourEdges
    let sides: [Edges] = preferLeft ? [.left, .right] : [.right, .left]
    var parked = frame

    for side in sides where !blocked.contains(side) {
      parked.origin.x = side == .left ? display.minX - frame.width + 1 : display.maxX - 1
      return parked
    }

    parked.origin.x = preferLeft ? display.minX - frame.width + 1 : display.maxX - 1
    if !blocked.contains(.bottom) {
      parked.origin.y = display.maxY - 1
    }
    return parked
  }
}
