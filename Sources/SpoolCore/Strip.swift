import CoreGraphics
import Foundation

public typealias WindowID = UInt64

public struct Column: Equatable, Sendable {
  public var windows: [WindowID]
  public var focusedRow = 0
  public var width: Double
  public var widthBeforeFullWidth: Double?
  public var fixedHeight: Double?

  public init(windows: [WindowID], width: Double) {
    self.windows = windows
    self.width = width
  }

  public var focusedWindow: WindowID? {
    windows.indices.contains(focusedRow) ? windows[focusedRow] : windows.first
  }
}

public struct StripGeometry: Equatable, Sendable {
  public var viewport: CGRect
  public var innerGap: Double
  public var outerGap: Double

  public init(viewport: CGRect, innerGap: Double, outerGap: Double) {
    self.viewport = viewport
    self.innerGap = innerGap
    self.outerGap = outerGap
  }

  public var usableWidth: Double { max(1, viewport.width - 2 * outerGap) }
  public var usableHeight: Double { max(1, viewport.height - 2 * outerGap) }

  public func points(forFraction fraction: Double) -> Double {
    max(1, fraction * (usableWidth + innerGap) - innerGap)
  }

  public func fraction(forPoints points: Double) -> Double {
    min(1, max(0.05, (points + innerGap) / (usableWidth + innerGap)))
  }
}

public struct Strip: Equatable, Sendable {
  public var columns: [Column] = []
  public var focusedColumn: Int?
  public var scroll = 0.0

  public init(columns: [Column] = [], focusedColumn: Int? = nil, scroll: Double = 0) {
    self.columns = columns
    self.focusedColumn = focusedColumn
    self.scroll = scroll
  }

  public var isEmpty: Bool { columns.isEmpty }

  public var windows: [WindowID] { columns.flatMap(\.windows) }

  public var focusedWindow: WindowID? {
    guard let focusedColumn, columns.indices.contains(focusedColumn) else { return nil }
    return columns[focusedColumn].focusedWindow
  }

  public func columnIndex(of window: WindowID) -> Int? {
    columns.firstIndex { $0.windows.contains(window) }
  }

  public func contains(_ window: WindowID) -> Bool {
    columnIndex(of: window) != nil
  }

  public mutating func insert(_ window: WindowID, width: Double, focus: Bool) {
    guard !contains(window) else { return }
    let index = focusedColumn.map { $0 + 1 } ?? columns.count
    columns.insert(Column(windows: [window], width: width), at: index)
    if focus || focusedColumn == nil {
      focusedColumn = index
    }
  }

  public mutating func append(_ window: WindowID, width: Double) {
    guard !contains(window) else { return }
    columns.append(Column(windows: [window], width: width))
    if focusedColumn == nil { focusedColumn = columns.count - 1 }
  }

  public mutating func remove(_ window: WindowID) {
    guard let index = columnIndex(of: window) else { return }
    columns[index].windows.removeAll { $0 == window }
    columns[index].focusedRow = min(columns[index].focusedRow, max(0, columns[index].windows.count - 1))
    guard columns[index].windows.isEmpty else { return }
    columns.remove(at: index)
    guard let focused = focusedColumn else { return }
    if columns.isEmpty {
      focusedColumn = nil
    } else if focused > index {
      focusedColumn = focused - 1
    } else if focused == index {
      focusedColumn = max(0, index - 1)
    }
  }

  public mutating func insert(_ window: WindowID, width: Double, at index: Int) {
    guard !contains(window) else { return }
    let index = min(max(0, index), columns.count)
    columns.insert(Column(windows: [window], width: width), at: index)
    focusedColumn = index
  }

  public func insertionIndex(forScreenX x: Double, _ geometry: StripGeometry) -> Int {
    let lefts = columnLefts(geometry)
    return columns.indices.filter { index in
      geometry.viewport.minX + lefts[index] - scroll + geometry.points(forFraction: columns[index].width) / 2 < x
    }.count
  }

  public mutating func moveColumn(from source: Int, to destination: Int) {
    guard source != destination, columns.indices.contains(source), columns.indices.contains(destination) else { return }
    let focused = focusedWindow
    columns.insert(columns.remove(at: source), at: destination)
    if let focused { focus(window: focused) }
  }

  @discardableResult
  public mutating func focus(window: WindowID) -> Bool {
    guard let index = columnIndex(of: window) else { return false }
    let row = columns[index].windows.firstIndex(of: window) ?? 0
    let changed = focusedColumn != index || columns[index].focusedRow != row
    focusedColumn = index
    columns[index].focusedRow = row
    return changed
  }

  public func columnLefts(_ geometry: StripGeometry) -> [Double] {
    var x = geometry.outerGap
    return columns.map { column in
      defer { x += geometry.points(forFraction: column.width) + geometry.innerGap }
      return x
    }
  }

  public func contentWidth(_ geometry: StripGeometry) -> Double {
    guard !columns.isEmpty else { return 0 }
    let widths = columns.reduce(0) { $0 + geometry.points(forFraction: $1.width) }
    return widths + Double(columns.count - 1) * geometry.innerGap + 2 * geometry.outerGap
  }

  public func maxScroll(_ geometry: StripGeometry) -> Double {
    max(0, contentWidth(geometry) - geometry.viewport.width)
  }

  public func clampedScroll(_ value: Double, _ geometry: StripGeometry) -> Double {
    let lower = min(0, scroll)
    let upper = max(maxScroll(geometry), scroll)
    return min(upper, max(lower, value))
  }

  public func revealScroll(column index: Int, mode: CenterMode, _ geometry: StripGeometry) -> Double {
    guard columns.indices.contains(index) else { return scroll }
    let left = columnLefts(geometry)[index]
    let width = geometry.points(forFraction: columns[index].width)
    let viewportWidth = geometry.viewport.width
    let fullyVisible = left - geometry.outerGap >= scroll - 0.5
      && left + width + geometry.outerGap <= scroll + viewportWidth + 0.5

    switch mode {
    case .always:
      return centeredScroll(column: index, geometry)
    case .onOverflow where !fullyVisible:
      return centeredScroll(column: index, geometry)
    case .never, .onOverflow:
      if fullyVisible { return scroll }
      if left - geometry.outerGap < scroll {
        return min(maxScroll(geometry), max(0, left - geometry.outerGap))
      }
      return min(maxScroll(geometry), max(0, left + width + geometry.outerGap - viewportWidth))
    }
  }

  public func centeredScroll(column index: Int, _ geometry: StripGeometry) -> Double {
    guard columns.indices.contains(index) else { return scroll }
    let left = columnLefts(geometry)[index]
    let width = geometry.points(forFraction: columns[index].width)
    return left + width / 2 - geometry.viewport.width / 2
  }

  public func snapScroll(near value: Double, _ geometry: StripGeometry) -> Double {
    let upper = maxScroll(geometry)
    var targets = columnLefts(geometry).map { $0 - geometry.outerGap }.filter { $0 <= upper }
    targets.append(upper)
    let clamped = min(upper, max(0, value))
    return targets.min { abs($0 - clamped) < abs($1 - clamped) } ?? clamped
  }

  public func straddles(seams: [Double], at scroll: Double, _ geometry: StripGeometry) -> Bool {
    let lefts = columnLefts(geometry)
    return columns.indices.contains { index in
      let left = geometry.viewport.minX + lefts[index] - scroll
      let right = left + geometry.points(forFraction: columns[index].width)
      return seams.contains { left < $0 - 0.5 && right > $0 + 0.5 }
    }
  }

  public func seamSafeSnapScroll(near value: Double, seams: [Double], keepVisible: Int?, _ geometry: StripGeometry) -> Double {
    let upper = maxScroll(geometry)
    let lefts = columnLefts(geometry)
    var candidates = lefts.map { $0 - geometry.outerGap } + [0, upper]
    for seam in seams {
      for (index, left) in lefts.enumerated() {
        let width = geometry.points(forFraction: columns[index].width)
        candidates.append(geometry.viewport.minX + left - seam - geometry.innerGap / 2)
        candidates.append(geometry.viewport.minX + left + width - seam + geometry.innerGap / 2)
      }
    }
    let valid = candidates
      .map { min(upper, max(0, $0)) }
      .filter { !straddles(seams: seams, at: $0, geometry) }
      .filter { scroll in keepVisible.map { fullyVisibleColumns(at: scroll, geometry).contains($0) } ?? true }
    guard let best = valid.min(by: { abs($0 - value) < abs($1 - value) }) else {
      return snapScroll(near: value, geometry)
    }
    return best
  }

  public func fullyVisibleColumns(at scroll: Double, _ geometry: StripGeometry) -> [Int] {
    let lefts = columnLefts(geometry)
    return columns.indices.filter { index in
      let left = lefts[index] - scroll
      let right = left + geometry.points(forFraction: columns[index].width)
      return left >= -0.5 && right <= geometry.viewport.width + 0.5
    }
  }

  public func leftmostVisibleColumn(at scroll: Double, _ geometry: StripGeometry) -> Int? {
    fullyVisibleColumns(at: scroll, geometry).first ?? columnNearestCenter(at: scroll, geometry)
  }

  public func columnNearestCenter(at scroll: Double, _ geometry: StripGeometry) -> Int? {
    let lefts = columnLefts(geometry)
    let center = scroll + geometry.viewport.width / 2
    let candidates = fullyVisibleColumns(at: scroll, geometry)
    let pool = candidates.isEmpty ? Array(columns.indices) : candidates
    return pool.min { a, b in
      let ca = lefts[a] + geometry.points(forFraction: columns[a].width) / 2
      let cb = lefts[b] + geometry.points(forFraction: columns[b].width) / 2
      return abs(ca - center) < abs(cb - center)
    }
  }
}
