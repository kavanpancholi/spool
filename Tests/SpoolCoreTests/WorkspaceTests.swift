import XCTest
@testable import SpoolCore

final class WorkspaceTests: XCTestCase {
  func strip(_ ids: [WindowID]) -> Strip {
    var strip = Strip()
    for id in ids { strip.append(id, width: 0.5) }
    strip.focusedColumn = ids.isEmpty ? nil : 0
    return strip
  }

  func test_going_down_from_the_last_workspace_opens_an_empty_one() {
    var stack = Workspaces()
    let target = stack.switchDown(from: strip([1, 2]))
    XCTAssertEqual(target, Strip())
    XCTAssertEqual(stack.above.map(\.windows), [[1, 2]])
    XCTAssertEqual(stack.position(current: target!).index, 1)
    XCTAssertEqual(stack.position(current: target!).count, 2)
  }

  func test_the_empty_workspace_at_the_bottom_is_the_last_stop() {
    var stack = Workspaces(above: [strip([1])])
    XCTAssertNil(stack.switchDown(from: Strip()))
  }

  func test_leaving_an_empty_workspace_drops_it() {
    var stack = Workspaces()
    let empty = stack.switchDown(from: strip([1]))!
    let back = stack.switchUp(from: empty)!
    XCTAssertEqual(back.windows, [1])
    XCTAssertTrue(stack.isEmpty)
    XCTAssertEqual(stack.position(current: back).count, 2)
  }

  func test_up_and_down_keep_the_order() {
    var stack = Workspaces(above: [strip([1]), strip([2])], below: [strip([4])])
    var current = strip([3])
    current = stack.switchUp(from: current)!
    XCTAssertEqual(current.windows, [2])
    XCTAssertEqual(stack.below.map(\.windows), [[3], [4]])
    current = stack.switchDown(from: current)!
    current = stack.switchDown(from: current)!
    XCTAssertEqual(current.windows, [4])
    XCTAssertEqual(stack.above.map(\.windows), [[1], [2], [3]])
  }

  func test_switching_to_a_window_brings_its_workspace() {
    var stack = Workspaces(above: [strip([1]), strip([2])], below: [strip([4]), strip([5])])
    let above = stack.switchTo(containing: 1, from: strip([3]))!
    XCTAssertEqual(above.windows, [1])
    XCTAssertEqual(stack.below.map(\.windows), [[2], [3], [4], [5]])
    let below = stack.switchTo(containing: 5, from: above)!
    XCTAssertEqual(below.windows, [5])
    XCTAssertEqual(stack.above.map(\.windows), [[1], [2], [3], [4]])
    XCTAssertNil(stack.switchTo(containing: 9, from: below))
  }

  func test_moving_a_window_down_takes_it_to_a_new_workspace() {
    var stack = Workspaces()
    var current = strip([1, 2])
    current.focusedColumn = 1
    let target = stack.moveFocused(.down, from: &current)!
    XCTAssertEqual(target.windows, [2])
    XCTAssertEqual(target.focusedWindow, 2)
    XCTAssertEqual(stack.above.map(\.windows), [[1]])
  }

  func test_moving_the_last_window_up_leaves_no_empty_workspace_behind() {
    var stack = Workspaces(above: [strip([1])])
    var current = strip([2])
    let target = stack.moveFocused(.up, from: &current)!
    XCTAssertEqual(target.windows, [1, 2])
    XCTAssertEqual(target.focusedWindow, 2)
    XCTAssertTrue(stack.isEmpty)
  }

  func test_moving_up_from_the_top_does_nothing() {
    var stack = Workspaces()
    var current = strip([1])
    XCTAssertNil(stack.moveFocused(.up, from: &current))
    XCTAssertEqual(current.windows, [1])
  }

  func test_closing_the_last_window_of_a_hidden_workspace_removes_it() {
    var stack = Workspaces(above: [strip([1])], below: [strip([2, 3])])
    stack.remove(1)
    stack.remove(2)
    XCTAssertTrue(stack.above.isEmpty)
    XCTAssertEqual(stack.below.map(\.windows), [[3]])
  }

  func test_hidden_windows_park_off_screen() {
    let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)
    let context = LayoutContext(geometry: geometry, displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 860), otherDisplays: [])
    let layout = strip([1, 2]).hiddenLayout(context)
    XCTAssertEqual(layout.count, 2)
    for placement in layout.values {
      XCTAssertFalse(placement.isVisible)
      XCTAssertLessThanOrEqual(placement.frame.intersection(context.displayFrame).area, placement.frame.height)
    }
  }

  func test_session_restores_hidden_workspaces() throws {
    let describe: (WindowID) -> SessionWindow? = { SessionWindow(cgID: UInt32($0) + 100, bundleID: "app") }
    let session = Session(
      strips: ["D": SessionStrip(strip([2]), describe: describe)],
      workspaces: ["D": SessionWorkspaces(above: [SessionStrip(strip([1]), describe: describe)], below: [SessionStrip(strip([3]), describe: describe)])]
    )
    let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
    let live = [7, 8, 9].map { LiveWindow(id: WindowID($0), cgID: UInt32($0 - 6 + 100), bundleID: "app") }
    let restored = decoded.restore(display: "D", live: live)!
    XCTAssertEqual(restored.strip.windows, [8])
    XCTAssertEqual(restored.workspaces.above.map(\.windows), [[7]])
    XCTAssertEqual(restored.workspaces.below.map(\.windows), [[9]])
  }

  func test_old_sessions_without_workspaces_still_load() throws {
    let json = #"{"version":1,"strips":{}}"#.data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(Session.self, from: json).workspaces, [:])
  }
}
