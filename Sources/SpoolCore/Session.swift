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
}

public struct SessionStrip: Codable, Equatable, Sendable {
  public var columns: [SessionColumn]
  public var focusedColumn: Int?
}

public struct Session: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version = Session.currentVersion
  public var strips: [String: SessionStrip] = [:]

  public init(strips: [String: SessionStrip] = [:]) {
    self.strips = strips
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
        fixedHeight: column.fixedHeight
      ))
    }
    self.init(columns: columns, focusedColumn: focused)
  }

  public func restore(_ live: [LiveWindow]) -> Strip {
    var unclaimed = live
    let savedIDs = Set(columns.flatMap { $0.windows.compactMap(\.cgID) })
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
      if index == self.focusedColumn { focusedColumn = strip.columns.count }
      strip.columns.append(column)
    }
    strip.focusedColumn = focusedColumn ?? (strip.columns.isEmpty ? nil : 0)
    return strip
  }
}
