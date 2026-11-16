import CoreGraphics
import Foundation

public typealias WindowID = UInt64

public struct Column: Equatable, Sendable {
  public var windows: [WindowID]
  public var focusedRow = 0
  public var width: Double
  public var widthBeforeFullWidth: Double?
  public var fixedHeight: Double?
  public var heights: [Double]?

  public init(windows: [WindowID], width: Double) {
    self.windows = windows
    self.width = width
  }

  public var focusedWindow: WindowID? {
    windows.indices.contains(focusedRow) ? windows[focusedRow] : windows.first
  }

  public static let minimumShare = 0.1

  public var shares: [Double] {
    guard let heights, heights.count == windows.count, windows.count > 1 else {
      return Array(repeating: 1 / Double(max(1, windows.count)), count: windows.count)
    }
    let total = heights.reduce(0, +)
    return heights.map { $0 / total }
  }

  public func rows(top: Double, height: Double, gap: Double) -> [(y: Double, height: Double)] {
    let available = height - Double(max(0, windows.count - 1)) * gap
    var y = top
    return shares.map { share in
      let row = (available * share).rounded(.down)
      defer { y += row + gap }
      return (y.rounded(), row)
    }
  }

  public mutating func setShare(_ share: Double, row: Int) {
    guard windows.count > 1, windows.indices.contains(row) else { return }
    let limit = 1 - Self.minimumShare * Double(windows.count - 1)
    let target = min(max(share, Self.minimumShare), limit)
    var current = shares
    let rest = 1 - current[row]
    for index in current.indices where index != row {
      current[index] = rest > 0 ? current[index] / rest * (1 - target) : (1 - target) / Double(windows.count - 1)
      current[index] = max(current[index], Self.minimumShare)
    }
    current[row] = target
    let total = current.reduce(0, +)
    heights = current.map { $0 / total }
  }

  mutating func removeRow(_ row: Int) {
    if var heights, heights.count == windows.count {
      heights.remove(at: row)
      self.heights = heights.count > 1 ? heights : nil
    } else {
      heights = nil
    }
    windows.remove(at: row)
  }

  mutating func swapRows(_ a: Int, _ b: Int) {
    windows.swapAt(a, b)
    if var heights, heights.count == windows.count {
      heights.swapAt(a, b)
      self.heights = heights
    }
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
    if let row = columns[index].windows.firstIndex(of: window) { columns[index].removeRow(row) }
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
  public mutating func consumeOrExpel(_ direction: Direction) -> Bool {
    guard let index = focusedColumn, columns.indices.contains(index), direction == .left || direction == .right,
      let window = columns[index].focusedWindow, columns[index].fixedHeight == nil
    else { return false }
    let column = columns[index]
    if column.windows.count > 1 {
      columns[index].removeRow(columns[index].focusedRow)
      columns[index].focusedRow = min(columns[index].focusedRow, columns[index].windows.count - 1)
      let destination = direction == .left ? index : index + 1
      columns.insert(Column(windows: [window], width: column.width), at: destination)
      focusedColumn = destination
      return true
    }
    let neighbour = direction == .left ? index - 1 : index + 1
    guard columns.indices.contains(neighbour), columns[neighbour].fixedHeight == nil else { return false }
    columns[neighbour].windows.append(window)
    columns[neighbour].heights = nil
    columns[neighbour].focusedRow = columns[neighbour].windows.count - 1
    columns.remove(at: index)
    focusedColumn = direction == .left ? neighbour : neighbour - 1
    return true
  }

  @discardableResult
  public mutating func moveWithinColumn(_ direction: Direction) -> Bool {
    guard let index = focusedColumn, columns.indices.contains(index) else { return false }
    let row = columns[index].focusedRow
    let target = direction == .up ? row - 1 : row + 1
    guard direction == .up || direction == .down, columns[index].windows.indices.contains(row),
      columns[index].windows.indices.contains(target)
    else { return false }
    columns[index].swapRows(row, target)
    columns[index].focusedRow = target
    return true
  }

  @discardableResult
  public mutating func drop(_ window: WindowID, atScreenX x: Double, _ geometry: StripGeometry) -> Bool {
    guard let source = columnIndex(of: window), columns[source].fixedHeight == nil else { return false }
    let before = self
    let width = columns[source].width
    remove(window)
    let lefts = columnLefts(geometry)
    let spans = columns.indices.map { index -> (minX: Double, maxX: Double) in
      let minX = geometry.viewport.minX + lefts[index] - scroll
      return (minX, minX + geometry.points(forFraction: columns[index].width))
    }
    if let target = spans.indices.first(where: { index in
      let quarter = (spans[index].maxX - spans[index].minX) / 4
      return x > spans[index].minX + quarter && x < spans[index].maxX - quarter
    }), columns[target].fixedHeight == nil {
      columns[target].windows.append(window)
      columns[target].heights = nil
      focusedColumn = target
      columns[target].focusedRow = columns[target].windows.count - 1
    } else {
      let index = spans.filter { ($0.minX + $0.maxX) / 2 < x }.count
      columns.insert(Column(windows: [window], width: width), at: index)
      focusedColumn = index
    }
    return self != before
  }

  @discardableResult
  public mutating func swapWindow(_ direction: Direction) -> Bool {
    guard let index = focusedColumn, columns.indices.contains(index), direction == .left || direction == .right else { return false }
    let neighbour = direction == .left ? index - 1 : index + 1
    guard columns.indices.contains(neighbour), columns[index].fixedHeight == nil, columns[neighbour].fixedHeight == nil else { return false }
    let row = columns[index].focusedRow
    let other = min(row, columns[neighbour].windows.count - 1)
    guard columns[index].windows.indices.contains(row), other >= 0 else { return false }
    let window = columns[index].windows[row]
    columns[index].windows[row] = columns[neighbour].windows[other]
    columns[neighbour].windows[other] = window
    focusedColumn = neighbour
    columns[neighbour].focusedRow = other
    return true
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

  mutating func growIntoFreeSpace(_ geometry: StripGeometry) -> Double? {
    guard let focused = focusedColumn, columns.indices.contains(focused) else { return nil }
    let lefts = columnLefts(geometry)
    func visible(_ index: Int) -> Bool {
      let right = lefts[index] + geometry.points(forFraction: columns[index].width)
      return lefts[index] - geometry.outerGap >= scroll - 0.5 && right + geometry.outerGap <= scroll + geometry.viewport.width + 0.5
    }
    var first = focused
    var last = focused
    if visible(focused) {
      while first > 0 && visible(first - 1) { first -= 1 }
      while last < columns.count - 1 && visible(last + 1) { last += 1 }
    }
    let others = (first...last).filter { $0 != focused }
      .reduce(0) { $0 + geometry.points(forFraction: columns[$1].width) + geometry.innerGap }
    let target = geometry.usableWidth - others
    guard target - geometry.points(forFraction: columns[focused].width) > 0.5 else { return nil }
    columns[focused].width = min(1, (target + geometry.innerGap) / (geometry.usableWidth + geometry.innerGap))
    columns[focused].widthBeforeFullWidth = nil
    return min(maxScroll(geometry), max(0, columnLefts(geometry)[first] - geometry.outerGap))
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
