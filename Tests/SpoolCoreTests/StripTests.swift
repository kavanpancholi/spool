import XCTest
@testable import SpoolCore

final class StripTests: XCTestCase {
  let geometry = StripGeometry(viewport: CGRect(x: 0, y: 25, width: 1000, height: 800), innerGap: 10, outerGap: 10)

  func makeStrip(_ count: Int, width: Double = 0.5) -> Strip {
    var strip = Strip()
    for id in 1...count { strip.append(WindowID(id), width: width) }
    return strip
  }

  func test_two_half_columns_fill_usable_width_exactly() {
    let half = geometry.points(forFraction: 0.5)
    XCTAssertEqual(half * 2 + geometry.innerGap, geometry.usableWidth, accuracy: 0.001)
    XCTAssertEqual(makeStrip(2).contentWidth(geometry), 1000, accuracy: 0.001)
  }

  func test_insert_goes_right_of_focused_column() {
    var strip = makeStrip(3)
    strip.focusedColumn = 0
    strip.insert(9, width: 0.5, focus: true)
    XCTAssertEqual(strip.windows, [1, 9, 2, 3])
    XCTAssertEqual(strip.focusedWindow, 9)
  }

  func test_background_insert_keeps_focus() {
    var strip = makeStrip(2)
    strip.focusedColumn = 1
    strip.insert(9, width: 0.5, focus: false)
    XCTAssertEqual(strip.windows, [1, 2, 9])
    XCTAssertEqual(strip.focusedWindow, 2)
  }

  func test_removing_focused_column_focuses_left_neighbour() {
    var strip = makeStrip(3)
    strip.focusedColumn = 1
    strip.remove(2)
    XCTAssertEqual(strip.focusedWindow, 1)
    strip.remove(1)
    XCTAssertEqual(strip.focusedWindow, 3)
    strip.remove(3)
    XCTAssertNil(strip.focusedColumn)
  }

  func test_removing_column_left_of_focus_keeps_same_window_focused() {
    var strip = makeStrip(3)
    strip.focusedColumn = 2
    strip.remove(1)
    XCTAssertEqual(strip.focusedWindow, 3)
  }

  func test_focus_right_scrolls_just_enough_to_reveal() {
    var strip = makeStrip(4)
    strip.focusedColumn = 1
    _ = strip.apply(.focus(.right), settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.focusedWindow, 3)
    let lefts = strip.columnLefts(geometry)
    let right = lefts[2] + geometry.points(forFraction: 0.5) + geometry.outerGap
    XCTAssertEqual(strip.scroll, right - 1000, accuracy: 0.001)
  }

  func test_focus_left_at_start_is_no_op() {
    var strip = makeStrip(2)
    strip.focusedColumn = 0
    let result = strip.apply(.focus(.left), settings: SpoolSettings(), geometry: geometry)
    XCTAssertTrue(result.handled)
    XCTAssertFalse(result.focusChanged)
    XCTAssertEqual(strip.scroll, 0)
  }

  func test_move_right_swaps_and_keeps_window_focused() {
    var strip = makeStrip(3)
    strip.focusedColumn = 0
    _ = strip.apply(.move(.right), settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.windows, [2, 1, 3])
    XCTAssertEqual(strip.focusedWindow, 1)
  }

  func test_move_first_and_last() {
    var strip = makeStrip(4)
    strip.focusedColumn = 2
    _ = strip.apply(.moveFirst, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.windows, [3, 1, 2, 4])
    _ = strip.apply(.moveLast, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.windows, [1, 2, 4, 3])
    XCTAssertEqual(strip.focusedWindow, 3)
  }

  func test_focus_index_out_of_range_is_unhandled() {
    var strip = makeStrip(2)
    strip.focusedColumn = 0
    XCTAssertFalse(strip.apply(.focusIndex(5), settings: SpoolSettings(), geometry: geometry).handled)
    XCTAssertTrue(strip.apply(.focusIndex(2), settings: SpoolSettings(), geometry: geometry).focusChanged)
  }

  func test_cycle_width_walks_presets_and_wraps() {
    var strip = makeStrip(1, width: 0.5)
    strip.focusedColumn = 0
    let settings = SpoolSettings()
    _ = strip.apply(.cycleWidth, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 2.0 / 3.0, accuracy: 0.0001)
    _ = strip.apply(.cycleWidth, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 1.0 / 3.0, accuracy: 0.0001)
  }

  func test_full_width_toggles_back() {
    var strip = makeStrip(1, width: 0.4)
    strip.focusedColumn = 0
    _ = strip.apply(.fullWidth, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 1)
    _ = strip.apply(.fullWidth, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 0.4)
  }

  func test_wider_and_narrower_clamp() {
    var strip = makeStrip(1, width: 0.95)
    strip.focusedColumn = 0
    _ = strip.apply(.wider, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 1)
    for _ in 0..<20 { _ = strip.apply(.narrower, settings: SpoolSettings(), geometry: geometry) }
    XCTAssertEqual(strip.columns[0].width, 0.1, accuracy: 0.0001)
  }

  func test_center_puts_column_mid_viewport() {
    var strip = makeStrip(3, width: 1.0 / 3.0)
    strip.focusedColumn = 0
    _ = strip.apply(.center, settings: SpoolSettings(), geometry: geometry)
    let placement = strip.layout(LayoutContext(geometry: geometry, displayFrame: geometry.viewport, neighbourEdges: []))
    let frame = placement[1]!.frame
    XCTAssertEqual(frame.midX, 500, accuracy: 1)
  }

  func test_center_mode_always_centres_on_focus() {
    var strip = makeStrip(5, width: 1.0 / 3.0)
    strip.focusedColumn = 0
    var settings = SpoolSettings()
    settings.centerMode = .always
    _ = strip.apply(.focus(.right), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.scroll, strip.centeredScroll(column: 1, geometry), accuracy: 0.001)
  }

  func test_snap_picks_nearest_column_edge() {
    let strip = makeStrip(4)
    let lefts = strip.columnLefts(geometry)
    XCTAssertEqual(strip.snapScroll(near: lefts[1] - 10 + 40, geometry), lefts[1] - 10, accuracy: 0.001)
    XCTAssertEqual(strip.snapScroll(near: 99_999, geometry), strip.maxScroll(geometry), accuracy: 0.001)
    XCTAssertEqual(strip.snapScroll(near: -500, geometry), 0, accuracy: 0.001)
  }

  func test_column_nearest_center_prefers_fully_visible() {
    let strip = makeStrip(4)
    let lefts = strip.columnLefts(geometry)
    XCTAssertEqual(strip.columnNearestCenter(at: lefts[2] - 10, geometry), 2)
  }

  func test_leftmost_fully_visible_column_after_scroll() {
    let strip = makeStrip(4)
    let lefts = strip.columnLefts(geometry)
    XCTAssertEqual(strip.leftmostVisibleColumn(at: lefts[1] - 10, geometry), 1)
    XCTAssertEqual(strip.leftmostVisibleColumn(at: lefts[1] - 10 + 50, geometry), 2)
  }

  func test_leftmost_visible_falls_back_when_column_wider_than_screen() {
    var strip = makeStrip(2, width: 1)
    strip.columns[0].width = 1
    XCTAssertEqual(strip.leftmostVisibleColumn(at: 300, geometry), 0)
  }
}
