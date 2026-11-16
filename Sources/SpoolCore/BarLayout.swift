import Foundation

public struct BarDrop: Equatable, Sendable {
  public let group: Int
  public let index: Int

  public init(group: Int, index: Int) {
    self.group = group
    self.index = index
  }
}

public struct BarLayout: Equatable, Sendable {
  public let groupCounts: [Int]
  public let icon: Double
  public let spacing: Double
  public let groupGap: Double
  public let padding: Double
  private let groupStarts: [Double]
  private let groupEnds: [Double]

  public init(groupCounts: [Int], icon: Double, spacing: Double, groupGap: Double, padding: Double) {
    self.groupCounts = groupCounts
    self.icon = icon
    self.spacing = spacing
    self.groupGap = groupGap
    self.padding = padding
    var starts: [Double] = []
    var ends: [Double] = []
    var x = padding
    for count in groupCounts {
      let slots = Double(max(count, 1))
      starts.append(x)
      let end = x + slots * icon + (slots - 1) * spacing
      ends.append(end)
      x = end + groupGap
    }
    groupStarts = starts
    groupEnds = ends
  }

  public var width: Double {
    (groupEnds.last ?? padding) + padding
  }

  public func center(group: Int, index: Int) -> Double {
    groupStarts[group] + Double(index) * (icon + spacing) + icon / 2
  }

  public func groupBounds(_ group: Int) -> ClosedRange<Double> {
    groupStarts[group]...groupEnds[group]
  }

  public func rubberBand(_ x: Double) -> Double {
    let low = padding + icon / 2
    let high = width - padding - icon / 2
    let reach = icon
    func stretch(_ overshoot: Double) -> Double {
      (1 - 1 / (overshoot * 0.55 / reach + 1)) * reach
    }
    if x < low { return low - stretch(low - x) }
    if x > high { return high + stretch(x - high) }
    return x
  }

  public func drop(atX x: Double, dragging: (group: Int, index: Int)) -> BarDrop {
    guard !groupCounts.isEmpty else { return BarDrop(group: 0, index: 0) }
    let group = groupCounts.indices.first { x < groupEnds[$0] + groupGap / 2 } ?? groupCounts.count - 1
    let index = (0..<groupCounts[group]).filter { slot in
      !(group == dragging.group && slot == dragging.index) && center(group: group, index: slot) < x
    }.count
    return BarDrop(group: group, index: index)
  }
}
