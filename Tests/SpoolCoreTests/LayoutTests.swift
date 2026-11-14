import XCTest
@testable import SpoolCore

final class LayoutTests: XCTestCase {
  let display = CGRect(x: 0, y: 0, width: 1000, height: 830)
  lazy var geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)

  func makeStrip(_ count: Int, width: Double = 0.5) -> Strip {
    var strip = Strip()
    for id in 1...count { strip.append(WindowID(id), width: width) }
    strip.focusedColumn = 0
    return strip
  }

  func test_visible_columns_sit_inside_gaps() {
    let strip = makeStrip(3)
    let placements = strip.layout(context())
    XCTAssertEqual(placements[1], .visible(CGRect(x: 10, y: 40, width: 485, height: 780)))
    XCTAssertEqual(placements[2], .visible(CGRect(x: 505, y: 40, width: 485, height: 780)))
  }

  let shorterOnRight = DisplayArea(frame: CGRect(x: 1000, y: 200, width: 800, height: 630))

  func context(_ others: [DisplayArea] = []) -> LayoutContext {
    LayoutContext(geometry: geometry, displayFrame: display, otherDisplays: others)
  }

  func test_column_spills_onto_a_display_tall_enough_to_hold_it() {
    var strip = makeStrip(3)
    strip.scroll = 300
    let tallerOnLeft = DisplayArea(frame: CGRect(x: -1000, y: -100, width: 1000, height: 1000))
    XCTAssertTrue(strip.layout(context([tallerOnLeft]))[1]!.isVisible)
    let shorterOnLeft = DisplayArea(frame: CGRect(x: -1000, y: 200, width: 1000, height: 630))
    XCTAssertFalse(strip.layout(context([shorterOnLeft]))[1]!.isVisible)
  }

  func test_offscreen_column_parks_in_bottom_right_corner() {
    let placements = makeStrip(3).layout(context())
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.minX, 999)
    XCTAssertEqual(frame.minY, 829)
    XCTAssertEqual(frame.width, 485)
  }

  func test_parks_in_bottom_left_corner_when_scrolled_past() {
    var strip = makeStrip(3)
    strip.scroll = strip.maxScroll(geometry)
    guard case .parked(let frame) = strip.layout(context())[1] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.maxX, 1)
    XCTAssertEqual(frame.minY, 829)
  }

  func test_partial_column_stays_visible_on_free_edge() {
    var strip = makeStrip(3)
    strip.scroll = 200
    let placements = strip.layout(context())
    XCTAssertTrue(placements[1]!.isVisible)
    XCTAssertTrue(placements[3]!.isVisible)
  }

  func test_column_spills_while_most_of_it_is_on_its_own_display() {
    var strip = makeStrip(3)
    strip.scroll = 300
    XCTAssertTrue(strip.layout(context([shorterOnRight]))[3]!.isVisible)
  }

  func test_column_parks_once_most_of_it_would_be_on_another_display() {
    var strip = makeStrip(3)
    strip.scroll = 200
    XCTAssertFalse(strip.layout(context([shorterOnRight]))[3]!.isVisible)
  }

  func test_never_parks_where_another_display_would_catch_the_window() {
    let placements = makeStrip(3).layout(context([shorterOnRight]))
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.maxX, 1)
    XCTAssertEqual(frame.minY, 829)
  }

  func test_display_below_parks_on_free_side_edge() {
    let below = DisplayArea(frame: CGRect(x: 0, y: 830, width: 1000, height: 800))
    guard case .parked(let frame) = makeStrip(3).layout(context([below]))[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.minX, 999)
    XCTAssertEqual(frame.minY, 40)
  }

  func test_stacked_column_splits_height() {
    var strip = makeStrip(1)
    strip.columns[0].windows = [1, 2]
    let placements = strip.layout(context())
    XCTAssertEqual(placements[1]!.frame.height, 385)
    XCTAssertEqual(placements[2]!.frame.minY, 40 + 385 + 10)
  }
}
