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
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: []))
    XCTAssertEqual(placements[1], .visible(CGRect(x: 10, y: 40, width: 485, height: 780)))
    XCTAssertEqual(placements[2], .visible(CGRect(x: 505, y: 40, width: 485, height: 780)))
  }

  func test_offscreen_column_parks_in_bottom_right_corner() {
    let strip = makeStrip(3)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: []))
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.minX, 999)
    XCTAssertEqual(frame.minY, 829)
    XCTAssertEqual(frame.width, 485)
  }

  func test_parks_in_bottom_left_corner_when_scrolled_past() {
    var strip = makeStrip(3)
    strip.scroll = strip.maxScroll(geometry)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: []))
    guard case .parked(let frame) = placements[1] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.maxX, 1)
    XCTAssertEqual(frame.minY, 829)
  }

  func test_partial_column_stays_visible_on_free_edge() {
    var strip = makeStrip(3)
    strip.scroll = 200
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: []))
    XCTAssertTrue(placements[1]!.isVisible)
    XCTAssertTrue(placements[3]!.isVisible)
  }

  func test_partial_column_spills_past_neighbour_display_edge() {
    var strip = makeStrip(3)
    strip.scroll = 200
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: [.right]))
    XCTAssertTrue(placements[3]!.isVisible)
  }

  func test_neighbour_on_the_right_still_parks_in_bottom_right_corner() {
    let strip = makeStrip(3)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: [.right]))
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.minX, 999)
    XCTAssertEqual(frame.minY, 829)
  }

  func test_display_below_parks_on_free_side_edge() {
    let strip = makeStrip(3)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: [.bottom]))
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.minX, 999)
    XCTAssertEqual(frame.minY, 40)
  }

  func test_display_below_and_right_parks_on_left_edge() {
    let strip = makeStrip(3)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: [.bottom, .right]))
    guard case .parked(let frame) = placements[3] else { return XCTFail("expected parked") }
    XCTAssertEqual(frame.maxX, 1)
  }

  func test_stacked_column_splits_height() {
    var strip = makeStrip(1)
    strip.columns[0].windows = [1, 2]
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: display, neighbourEdges: []))
    XCTAssertEqual(placements[1]!.frame.height, 385)
    XCTAssertEqual(placements[2]!.frame.minY, 40 + 385 + 10)
  }
}
