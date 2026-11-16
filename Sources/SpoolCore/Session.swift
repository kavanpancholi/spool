import Foundation

public struct SessionWindow: Codable, Equatable, Sendable {
  public let cgID: UInt32?
  public let bundleID: String?

  public init(cgID: UInt32?, bundleID: String?) {
    self.cgID = cgID
    self.bundleID = bundleID
  }
}

public struct SessionColumn: Codable, Equatable, Sendable {
  public var windows: [SessionWindow]
  public var focusedRow: Int
  public var width: Double
  public var widthBeforeFullWidth: Double?
  public var fixedHeight: Double?
  public var heights: [Double]?
}

public struct SessionStrip: Codable, Equatable, Sendable {
  public var columns: [SessionColumn]
  public var focusedColumn: Int?
}

public struct SessionWorkspaces: Codable, Equatable, Sendable {
  public var above: [SessionStrip]
  public var below: [SessionStrip]

  public init(above: [SessionStrip], below: [SessionStrip]) {
    self.above = above
    self.below = below
  }
}

public struct Session: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version = Session.currentVersion
  public var strips: [String: SessionStrip] = [:]
  public var workspaces: [String: SessionWorkspaces] = [:]

  public init(strips: [String: SessionStrip] = [:], workspaces: [String: SessionWorkspaces] = [:]) {
    self.strips = strips
    self.workspaces = workspaces
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    strips = try c.decodeIfPresent([String: SessionStrip].self, forKey: .strips) ?? [:]
    workspaces = try c.decodeIfPresent([String: SessionWorkspaces].self, forKey: .workspaces) ?? [:]
  }

  public func restore(display: String, live: [LiveWindow]) -> (strip: Strip, workspaces: Workspaces)? {
    guard let current = strips[display] else { return nil }
    let saved = workspaces[display] ?? SessionWorkspaces(above: [], below: [])
    let all = saved.above + [current] + saved.below
    let reserved = Set(all.flatMap { $0.columns.flatMap { $0.windows.compactMap(\.cgID) } })
    var unclaimed = live
    let strip = current.restore(claiming: &unclaimed, reserved: reserved)
    let above = saved.above.map { $0.restore(claiming: &unclaimed, reserved: reserved) }
    let below = saved.below.map { $0.restore(claiming: &unclaimed, reserved: reserved) }
    return (strip, Workspaces(above: above, below: below))
  }
}

public struct LiveWindow: Equatable, Sendable {
  public let id: WindowID
  public let cgID: UInt32?
  public let bundleID: String?

  public init(id: WindowID, cgID: UInt32?, bundleID: String?) {
    self.id = id
    self.cgID = cgID
    self.bundleID = bundleID
  }
}

extension SessionStrip {
  public init(_ strip: Strip, describe: (WindowID) -> SessionWindow?) {
    var focused = strip.focusedColumn
    var columns: [SessionColumn] = []
    for (index, column) in strip.columns.enumerated() {
      let windows = column.windows.compactMap(describe)
      guard !windows.isEmpty else {
        if let current = focused, current >= index { focused = current == index ? nil : current - 1 }
        continue
      }
      columns.append(SessionColumn(
        windows: windows,
        focusedRow: min(column.focusedRow, windows.count - 1),
        width: column.width,
        widthBeforeFullWidth: column.widthBeforeFullWidth,
        fixedHeight: column.fixedHeight,
        heights: windows.count == column.windows.count ? column.heights : nil
      ))
    }
    self.init(columns: columns, focusedColumn: focused)
  }

  public func restore(_ live: [LiveWindow]) -> Strip {
    var unclaimed = live
    return restore(claiming: &unclaimed, reserved: Set(columns.flatMap { $0.windows.compactMap(\.cgID) }))
  }

  public func restore(claiming unclaimed: inout [LiveWindow], reserved savedIDs: Set<UInt32>) -> Strip {
    func claim(_ saved: SessionWindow) -> WindowID? {
      let index = saved.cgID.flatMap { cgID in unclaimed.firstIndex { $0.cgID == cgID } }
        ?? unclaimed.firstIndex { saved.bundleID != nil && $0.bundleID == saved.bundleID && !savedIDs.contains($0.cgID ?? 0) }
      guard let index else { return nil }
      return unclaimed.remove(at: index).id
    }

    var strip = Strip()
    var focusedColumn: Int?
    for (index, saved) in columns.enumerated() {
      let windows = saved.windows.compactMap(claim)
      guard !windows.isEmpty else { continue }
      var column = Column(windows: windows, width: saved.width)
      column.focusedRow = min(saved.focusedRow, windows.count - 1)
      column.widthBeforeFullWidth = saved.widthBeforeFullWidth
      column.fixedHeight = saved.fixedHeight
      column.heights = windows.count == saved.windows.count ? saved.heights : nil
      if index == self.focusedColumn { focusedColumn = strip.columns.count }
      strip.columns.append(column)
    }
    strip.focusedColumn = focusedColumn ?? (strip.columns.isEmpty ? nil : 0)
    return strip
  }
}
