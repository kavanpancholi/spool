import XCTest
@testable import SpoolCore

final class SessionTests: XCTestCase {
  func saved() -> SessionStrip {
    var strip = Strip()
    strip.append(1, width: 0.5)
    strip.append(2, width: 0.3)
    strip.append(3, width: 0.4)
    _ = strip.consumeOrExpel(.left)
    strip.focusedColumn = 1
    let cgIDs: [WindowID: UInt32] = [1: 101, 2: 102, 3: 103]
    let bundles: [WindowID: String] = [1: "com.brave", 2: "com.slack", 3: "com.linear"]
    strip.focusedColumn = 0
    _ = strip.consumeOrExpel(.right)
    strip.focus(window: 3)
    return SessionStrip(strip) { SessionWindow(cgID: cgIDs[$0], bundleID: bundles[$0]) }
  }

  func test_round_trip_keeps_order_widths_stacks_and_focus() {
    let session = saved()
    let restored = session.restore([
      LiveWindow(id: 9, cgID: 103, bundleID: "com.linear"),
      LiveWindow(id: 7, cgID: 101, bundleID: "com.brave"),
      LiveWindow(id: 8, cgID: 102, bundleID: "com.slack"),
    ])
    XCTAssertEqual(restored.columns.map(\.windows), session.columns.map { $0.windows.map { ["101": 7, "102": 8, "103": 9]["\($0.cgID!)"]! as WindowID } })
    XCTAssertEqual(restored.columns.map(\.width), session.columns.map(\.width))
    XCTAssertEqual(restored.focusedWindow, 9)
  }

  func test_closed_windows_drop_out_and_empty_columns_vanish() {
    let session = SessionStrip(columns: [
      SessionColumn(windows: [SessionWindow(cgID: 1, bundleID: "a")], focusedRow: 0, width: 0.5),
      SessionColumn(windows: [SessionWindow(cgID: 2, bundleID: "b")], focusedRow: 0, width: 0.3),
    ], focusedColumn: 1)
    let restored = session.restore([LiveWindow(id: 5, cgID: 2, bundleID: "b")])
    XCTAssertEqual(restored.columns.map(\.windows), [[5]])
    XCTAssertEqual(restored.focusedWindow, 5)
  }

  func test_a_relaunched_app_takes_its_old_slot_by_bundle() {
    let session = SessionStrip(columns: [
      SessionColumn(windows: [SessionWindow(cgID: 1, bundleID: "a")], focusedRow: 0, width: 0.5),
      SessionColumn(windows: [SessionWindow(cgID: 2, bundleID: "b")], focusedRow: 0, width: 0.7),
    ], focusedColumn: 0)
    let restored = session.restore([
      LiveWindow(id: 5, cgID: 1, bundleID: "a"),
      LiveWindow(id: 6, cgID: 99, bundleID: "b"),
    ])
    XCTAssertEqual(restored.columns.map(\.windows), [[5], [6]])
    XCTAssertEqual(restored.columns[1].width, 0.7)
  }

  func test_a_live_window_with_a_saved_id_is_never_taken_by_bundle() {
    let session = SessionStrip(columns: [
      SessionColumn(windows: [SessionWindow(cgID: 1, bundleID: "a")], focusedRow: 0, width: 0.5),
      SessionColumn(windows: [SessionWindow(cgID: 2, bundleID: "a")], focusedRow: 0, width: 0.3),
    ], focusedColumn: 0)
    let restored = session.restore([LiveWindow(id: 6, cgID: 2, bundleID: "a")])
    XCTAssertEqual(restored.columns.map(\.windows), [[6]])
    XCTAssertEqual(restored.columns[0].width, 0.3)
  }

  func test_session_survives_encoding() throws {
    let session = Session(strips: ["display": saved()])
    let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
    XCTAssertEqual(decoded, session)
  }
}
