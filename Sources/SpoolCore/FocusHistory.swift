public struct FocusHistory: Equatable, Sendable {
  public private(set) var windows: [WindowID] = []
  public let limit: Int

  public init(limit: Int = 30) {
    self.limit = limit
  }

  public mutating func record(_ id: WindowID) {
    guard windows.last != id else { return }
    windows.removeAll { $0 == id }
    windows.append(id)
    if windows.count > limit { windows.removeFirst(windows.count - limit) }
  }

  public mutating func forget(_ id: WindowID) {
    windows.removeAll { $0 == id }
  }

  public func previous(current: WindowID?, where isAvailable: (WindowID) -> Bool) -> WindowID? {
    windows.reversed().first { $0 != current && isAvailable($0) }
  }
}
