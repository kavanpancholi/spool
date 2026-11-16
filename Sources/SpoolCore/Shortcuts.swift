import Foundation

public struct Shortcut: Hashable, Codable, Sendable {
  public var keyCode: UInt32
  public var modifiers: ModifierState
  public var command: Command

  public init(_ keyCode: UInt32, _ modifiers: ModifierState, _ command: Command) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.command = command
  }
}

public enum KeyCode {
  public static let h: UInt32 = 4
  public static let j: UInt32 = 38
  public static let k: UInt32 = 40
  public static let l: UInt32 = 37
  public static let left: UInt32 = 123
  public static let right: UInt32 = 124
  public static let down: UInt32 = 125
  public static let up: UInt32 = 126
  public static let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
  public static let equal: UInt32 = 24
  public static let minus: UInt32 = 27
  public static let r: UInt32 = 15
  public static let f: UInt32 = 3
  public static let c: UInt32 = 8
  public static let n: UInt32 = 45
  public static let q: UInt32 = 12
  public static let t: UInt32 = 17
  public static let tab: UInt32 = 48
  public static let leftBracket: UInt32 = 33
  public static let rightBracket: UInt32 = 30
  public static let e: UInt32 = 14
  public static let v: UInt32 = 9
  public static let g: UInt32 = 5
  public static let u: UInt32 = 32
  public static let i: UInt32 = 34
  public static let pageUp: UInt32 = 116
  public static let pageDown: UInt32 = 121

  public static func name(_ code: UInt32) -> String {
    switch code {
    case h: "H"
    case j: "J"
    case k: "K"
    case l: "L"
    case left: "←"
    case right: "→"
    case down: "↓"
    case up: "↑"
    case equal: "="
    case minus: "-"
    case r: "R"
    case f: "F"
    case c: "C"
    case n: "N"
    case q: "Q"
    case t: "T"
    case tab: "⇥"
    case leftBracket: "["
    case rightBracket: "]"
    case e: "E"
    case v: "V"
    case g: "G"
    case u: "U"
    case i: "I"
    case pageUp: "⇞"
    case pageDown: "⇟"
    default:
      if let index = digits.firstIndex(of: code) { "\(index + 1)" } else { "#\(code)" }
    }
  }
}

extension ModifierState {
  public var symbols: String {
    var result = ""
    if contains(.control) { result += "⌃" }
    if contains(.option) { result += "⌥" }
    if contains(.shift) { result += "⇧" }
    if contains(.command) { result += "⌘" }
    return result
  }
}

extension Shortcut {
  public var display: String { modifiers.symbols + KeyCode.name(keyCode) }

  public static let defaults: [Shortcut] = {
    let base: ModifierState = [.control, .option]
    let move: ModifierState = [.control, .option, .shift]
    var list: [Shortcut] = []
    let directions: [(Direction, [UInt32])] = [
      (.left, [KeyCode.h, KeyCode.left]),
      (.down, [KeyCode.j, KeyCode.down]),
      (.up, [KeyCode.k, KeyCode.up]),
      (.right, [KeyCode.l, KeyCode.right]),
    ]
    for (direction, keys) in directions {
      for key in keys {
        list.append(Shortcut(key, base, .focus(direction)))
        list.append(Shortcut(key, move, .move(direction)))
      }
    }
    list.append(Shortcut(KeyCode.left, base.union(.command), .focusFirst))
    list.append(Shortcut(KeyCode.right, base.union(.command), .focusLast))
    list.append(Shortcut(KeyCode.left, move.union(.command), .moveFirst))
    list.append(Shortcut(KeyCode.right, move.union(.command), .moveLast))
    for (offset, key) in KeyCode.digits.enumerated() {
      list.append(Shortcut(key, base, .focusIndex(offset + 1)))
    }
    list.append(Shortcut(KeyCode.tab, base, .focusPrevious))
    list.append(Shortcut(KeyCode.leftBracket, base, .consumeOrExpel(.left)))
    list.append(Shortcut(KeyCode.rightBracket, base, .consumeOrExpel(.right)))
    list.append(Shortcut(KeyCode.leftBracket, move, .swap(.left)))
    list.append(Shortcut(KeyCode.rightBracket, move, .swap(.right)))
    list.append(Shortcut(KeyCode.equal, move, .taller))
    list.append(Shortcut(KeyCode.minus, move, .shorter))
    list.append(Shortcut(KeyCode.e, base, .equalizeHeights))
    list.append(Shortcut(KeyCode.r, move, .cycleHeight))
    list.append(Shortcut(KeyCode.f, move, .keepOwnHeight))
    list.append(Shortcut(KeyCode.v, base, .focusFloating))
    list.append(Shortcut(KeyCode.r, base, .cycleWidth))
    list.append(Shortcut(KeyCode.f, base, .fullWidth))
    list.append(Shortcut(KeyCode.g, base, .growIntoFreeSpace))
    list.append(Shortcut(KeyCode.c, base, .center))
    list.append(Shortcut(KeyCode.equal, base, .wider))
    list.append(Shortcut(KeyCode.minus, base, .narrower))
    list.append(Shortcut(KeyCode.u, base, .focusWorkspace(.down)))
    list.append(Shortcut(KeyCode.i, base, .focusWorkspace(.up)))
    list.append(Shortcut(KeyCode.pageDown, base, .focusWorkspace(.down)))
    list.append(Shortcut(KeyCode.pageUp, base, .focusWorkspace(.up)))
    list.append(Shortcut(KeyCode.u, move, .moveToWorkspace(.down)))
    list.append(Shortcut(KeyCode.i, move, .moveToWorkspace(.up)))
    list.append(Shortcut(KeyCode.pageDown, move, .moveToWorkspace(.down)))
    list.append(Shortcut(KeyCode.pageUp, move, .moveToWorkspace(.up)))
    list.append(Shortcut(KeyCode.n, base, .sendToNextDisplay))
    list.append(Shortcut(KeyCode.t, base, .toggleFloat))
    list.append(Shortcut(KeyCode.q, base, .toggleEnabled))
    return list
  }()
}

public struct CheatsheetEntry: Equatable, Sendable {
  public let title: String
  public let keys: [String]
}

extension Shortcut {
  public static func cheatsheet(_ shortcuts: [Shortcut]) -> [CheatsheetEntry] {
    var entries: [CheatsheetEntry] = []
    var indexOf: [String: Int] = [:]
    for shortcut in shortcuts {
      let title: String
      let key: String
      if case .focusIndex = shortcut.command {
        title = "Focus window 1 to 9"
        key = shortcut.modifiers.symbols + "1…9"
      } else {
        title = shortcut.command.title
        key = shortcut.display
      }
      if let index = indexOf[title] {
        if !entries[index].keys.contains(key) {
          entries[index] = CheatsheetEntry(title: title, keys: entries[index].keys + [key])
        }
      } else {
        indexOf[title] = entries.count
        entries.append(CheatsheetEntry(title: title, keys: [key]))
      }
    }
    return entries
  }
}
