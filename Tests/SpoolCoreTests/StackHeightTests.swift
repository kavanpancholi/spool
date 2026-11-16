import XCTest
@testable import SpoolCore

final class StackHeightTests: XCTestCase {
  let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)
  let settings = SpoolSettings()

  func stacked() -> Strip {
    var strip = Strip()
    strip.append(1, width: 0.5)
    strip.append(2, width: 0.5)
    strip.append(3, width: 0.5)
    strip.focusedColumn = 1
    _ = strip.consumeOrExpel(.left)
    return strip
  }

  func rows(_ strip: Strip, column: Int = 0) -> [Double] {
    strip.columns[column].rows(top: 0, height: 1010, gap: 10).map(\.height)
  }

  func test_taller_and_shorter_change_the_focused_row_share() {
    var strip = stacked()
    _ = strip.apply(.taller, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].shares[1], 0.6, accuracy: 0.001)
    XCTAssertEqual(rows(strip), [400, 600])
    _ = strip.apply(.shorter, settings: settings, geometry: geometry)
    _ = strip.apply(.shorter, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].shares[1], 0.4, accuracy: 0.001)
  }

  func test_a_row_never_shrinks_below_the_minimum() {
    var strip = stacked()
    for _ in 0..<20 { _ = strip.apply(.shorter, settings: settings, geometry: geometry) }
    XCTAssertEqual(strip.columns[0].shares[1], Column.minimumShare, accuracy: 0.001)
    for _ in 0..<20 { _ = strip.apply(.taller, settings: settings, geometry: geometry) }
    XCTAssertEqual(strip.columns[0].shares[0], Column.minimumShare, accuracy: 0.001)
  }

  func test_equalize_and_cycle_presets() {
    var strip = stacked()
    _ = strip.apply(.cycleHeight, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].shares[1], 2.0 / 3.0, accuracy: 0.001)
    _ = strip.apply(.cycleHeight, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].shares[1], 1.0 / 3.0, accuracy: 0.001)
    _ = strip.apply(.equalizeHeights, settings: settings, geometry: geometry)
    XCTAssertNil(strip.columns[0].heights)
    XCTAssertEqual(rows(strip), [500, 500])
  }

  func test_heights_follow_their_window_when_reordered_and_drop_when_it_leaves() {
    var strip = stacked()
    _ = strip.apply(.taller, settings: settings, geometry: geometry)
    _ = strip.apply(.move(.up), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].windows, [2, 1])
    XCTAssertEqual(strip.columns[0].shares[0], 0.6, accuracy: 0.001)
    strip.remove(1)
    XCTAssertNil(strip.columns[0].heights)
  }

  func test_swap_trades_places_with_the_same_row_of_the_next_column() {
    var strip = stacked()
    strip.focus(window: 2)
    XCTAssertTrue(strip.apply(.swap(.right), settings: settings, geometry: geometry).layoutChanged)
    XCTAssertEqual(strip.columns.map(\.windows), [[1, 3], [2]])
    XCTAssertEqual(strip.focusedWindow, 2)
    XCTAssertFalse(strip.swapWindow(.right))
  }

  func test_session_keeps_stack_heights() {
    var strip = stacked()
    _ = strip.apply(.taller, settings: settings, geometry: geometry)
    let saved = SessionStrip(strip) { SessionWindow(cgID: UInt32($0), bundleID: nil) }
    let restored = saved.restore([LiveWindow(id: 1, cgID: 1, bundleID: nil), LiveWindow(id: 2, cgID: 2, bundleID: nil)])
    XCTAssertEqual(restored.columns[0].shares[1], 0.6, accuracy: 0.001)
  }
}
