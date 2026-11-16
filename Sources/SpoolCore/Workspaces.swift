import Foundation

public struct Workspaces: Equatable, Sendable {
  public var above: [Strip]
  public var below: [Strip]

  public init(above: [Strip] = [], below: [Strip] = []) {
    self.above = above.filter { !$0.isEmpty }
    self.below = below.filter { !$0.isEmpty }
  }

  public var isEmpty: Bool { above.isEmpty && below.isEmpty }

  public var windows: [WindowID] { (above + below).flatMap(\.windows) }

  public func contains(_ id: WindowID) -> Bool {
    above.contains { $0.contains(id) } || below.contains { $0.contains(id) }
  }

  public func position(current: Strip) -> (index: Int, count: Int) {
    let count = above.count + 1 + below.count + (current.isEmpty && below.isEmpty ? 0 : 1)
    return (above.count, count)
  }

  public mutating func remove(_ id: WindowID) {
    for index in above.indices { above[index].remove(id) }
    for index in below.indices { below[index].remove(id) }
    above.removeAll(where: \.isEmpty)
    below.removeAll(where: \.isEmpty)
  }

  public mutating func switchDown(from current: Strip) -> Strip? {
    guard !(current.isEmpty && below.isEmpty) else { return nil }
    if !current.isEmpty { above.append(current) }
    return below.isEmpty ? Strip() : below.removeFirst()
  }

  public mutating func switchUp(from current: Strip) -> Strip? {
    guard !above.isEmpty else { return nil }
    if !current.isEmpty { below.insert(current, at: 0) }
    return above.removeLast()
  }

  public mutating func switchTo(containing id: WindowID, from current: Strip) -> Strip? {
    if let index = above.firstIndex(where: { $0.contains(id) }) {
      var target: Strip?
      while above.count > index { target = switchUp(from: target ?? current) }
      return target
    }
    if let index = below.firstIndex(where: { $0.contains(id) }) {
      var target = current
      for _ in 0...index { target = switchDown(from: target) ?? target }
      return target
    }
    return nil
  }

  public mutating func moveFocused(_ direction: Direction, from current: inout Strip) -> Strip? {
    guard direction == .up || direction == .down, let id = current.focusedWindow,
      let column = current.columnIndex(of: id)
    else { return nil }
    if direction == .up && above.isEmpty { return nil }
    let width = current.columns[column].width
    current.remove(id)
    let target = direction == .down ? switchDown(from: current) ?? Strip() : switchUp(from: current)
    guard var target else { return nil }
    let index = target.focusedColumn.map { $0 + 1 } ?? target.columns.count
    target.insert(id, width: width, at: min(index, target.columns.count))
    target.focus(window: id)
    return target
  }
}
