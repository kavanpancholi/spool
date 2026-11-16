import Foundation

public enum Direction: String, Codable, CaseIterable, Sendable {
  case left, right, up, down
}

public enum Command: Hashable, Codable, Sendable {
  case focus(Direction)
  case focusFirst
  case focusLast
  case focusIndex(Int)
  case focusPrevious
  case move(Direction)
  case moveFirst
  case moveLast
  case consumeOrExpel(Direction)
  case swap(Direction)
  case taller
  case shorter
  case equalizeHeights
  case cycleHeight
  case keepOwnHeight
  case focusFloating
  case cycleWidth
  case wider
  case narrower
  case fullWidth
  case center
  case sendToNextDisplay
  case toggleFloat
  case toggleEnabled

  public var title: String {
    switch self {
    case .focus(let d): "Focus \(d.rawValue)"
    case .focusFirst: "Focus first window"
    case .focusLast: "Focus last window"
    case .focusIndex(let i): "Focus window \(i)"
    case .focusPrevious: "Back to previous window"
    case .move(let d): "Move window \(d.rawValue)"
    case .moveFirst: "Move window to start"
    case .moveLast: "Move window to end"
    case .swap(let d): "Swap with the \(d.rawValue) column"
    case .taller: "Taller"
    case .shorter: "Shorter"
    case .equalizeHeights: "Equal heights in the stack"
    case .cycleHeight: "Cycle preset heights"
    case .keepOwnHeight: "Keep own height or fill"
    case .focusFloating: "Focus next floating window"
    case .consumeOrExpel(let d): d == .left ? "Stack into the left column, or take out to the left" : "Stack into the right column, or take out to the right"
    case .cycleWidth: "Cycle width"
    case .wider: "Wider"
    case .narrower: "Narrower"
    case .fullWidth: "Full width"
    case .center: "Centre column"
    case .sendToNextDisplay: "Send to next display"
    case .toggleFloat: "Float or tile window"
    case .toggleEnabled: "Stop or start Spool"
    }
  }
}

public struct CommandResult: Equatable, Sendable {
  public var handled: Bool
  public var focusChanged: Bool
  public var layoutChanged: Bool

  public static let unhandled = CommandResult(handled: false, focusChanged: false, layoutChanged: false)
}

extension Strip {
  public mutating func apply(
    _ command: Command,
    settings: SpoolSettings,
    geometry: StripGeometry
  ) -> CommandResult {
    guard let focused = focusedColumn, columns.indices.contains(focused) else {
      return .unhandled
    }
    let before = self

    switch command {
    case .focus(.left):
      focusedColumn = max(0, focused - 1)
    case .focus(.right):
      focusedColumn = min(columns.count - 1, focused + 1)
    case .focus(.up):
      columns[focused].focusedRow = max(0, columns[focused].focusedRow - 1)
    case .focus(.down):
      columns[focused].focusedRow = min(columns[focused].windows.count - 1, columns[focused].focusedRow + 1)
    case .focusFirst:
      focusedColumn = 0
    case .focusLast:
      focusedColumn = columns.count - 1
    case .focusIndex(let number):
      guard columns.indices.contains(number - 1) else { return .unhandled }
      focusedColumn = number - 1
    case .move(.left):
      guard focused > 0 else { break }
      columns.swapAt(focused, focused - 1)
      focusedColumn = focused - 1
    case .move(.right):
      guard focused < columns.count - 1 else { break }
      columns.swapAt(focused, focused + 1)
      focusedColumn = focused + 1
    case .move(.up), .move(.down):
      if case .move(let direction) = command { moveWithinColumn(direction) }
    case .consumeOrExpel(let direction):
      guard consumeOrExpel(direction) else { return .unhandled }
    case .swap(let direction):
      guard swapWindow(direction) else { return .unhandled }
    case .taller, .shorter:
      let row = columns[focused].focusedRow
      let step = command == .taller ? settings.heightStep : -settings.heightStep
      columns[focused].setShare(columns[focused].shares[row] + step, row: row)
    case .equalizeHeights:
      columns[focused].heights = nil
    case .cycleHeight:
      let row = columns[focused].focusedRow
      let current = columns[focused].shares[row]
      let presets = [1.0 / 3.0, 0.5, 2.0 / 3.0]
      columns[focused].setShare(presets.first { $0 > current + 0.01 } ?? presets[0], row: row)
    case .moveFirst:
      let column = columns.remove(at: focused)
      columns.insert(column, at: 0)
      focusedColumn = 0
    case .moveLast:
      let column = columns.remove(at: focused)
      columns.append(column)
      focusedColumn = columns.count - 1
    case .cycleWidth:
      let presets = settings.sanitizedWidthPresets
      let current = columns[focused].width
      let next = presets.first { $0 > current + 0.01 } ?? presets[0]
      columns[focused].width = next
      columns[focused].widthBeforeFullWidth = nil
    case .wider:
      columns[focused].width = min(1, columns[focused].width + settings.widthStep)
      columns[focused].widthBeforeFullWidth = nil
    case .narrower:
      columns[focused].width = max(0.1, columns[focused].width - settings.widthStep)
      columns[focused].widthBeforeFullWidth = nil
    case .fullWidth:
      if let previous = columns[focused].widthBeforeFullWidth {
        columns[focused].width = previous
        columns[focused].widthBeforeFullWidth = nil
      } else {
        columns[focused].widthBeforeFullWidth = columns[focused].width
        columns[focused].width = 1
      }
    case .center:
      scroll = centeredScroll(column: focused, geometry)
      return CommandResult(handled: true, focusChanged: false, layoutChanged: true)
    case .sendToNextDisplay, .toggleFloat, .toggleEnabled, .focusPrevious, .keepOwnHeight, .focusFloating:
      return .unhandled
    }

    if let index = focusedColumn {
      scroll = revealScroll(column: index, mode: settings.centerMode, geometry)
    }
    return CommandResult(
      handled: true,
      focusChanged: focusedWindow != before.focusedWindow,
      layoutChanged: self != before
    )
  }
}
