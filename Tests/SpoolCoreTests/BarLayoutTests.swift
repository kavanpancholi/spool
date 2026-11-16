import XCTest
@testable import SpoolCore

final class BarLayoutTests: XCTestCase {
  let layout = BarLayout(groupCounts: [2, 1], icon: 30, spacing: 10, groupGap: 30, padding: 5)

  func test_centres_include_group_gap() {
    XCTAssertEqual(layout.center(group: 0, index: 0), 20)
    XCTAssertEqual(layout.center(group: 0, index: 1), 60)
    XCTAssertEqual(layout.center(group: 1, index: 0), 120)
    XCTAssertEqual(layout.width, 140)
  }

  func test_empty_group_keeps_a_drop_slot() {
    let empty = BarLayout(groupCounts: [1, 0], icon: 30, spacing: 10, groupGap: 30, padding: 5)
    XCTAssertEqual(empty.width, 100)
    XCTAssertEqual(empty.drop(atX: 80, dragging: (0, 0)), BarDrop(group: 1, index: 0))
  }

  func test_drop_within_same_group_ignores_dragged_tile() {
    XCTAssertEqual(layout.drop(atX: 70, dragging: (0, 0)), BarDrop(group: 0, index: 1))
    XCTAssertEqual(layout.drop(atX: 10, dragging: (0, 1)), BarDrop(group: 0, index: 0))
  }

  func test_drop_across_groups_counts_tiles_left_of_pointer() {
    XCTAssertEqual(layout.drop(atX: 110, dragging: (0, 0)), BarDrop(group: 1, index: 0))
    XCTAssertEqual(layout.drop(atX: 135, dragging: (0, 0)), BarDrop(group: 1, index: 1))
    XCTAssertEqual(layout.drop(atX: 30, dragging: (1, 0)), BarDrop(group: 0, index: 1))
  }

  func test_drop_outside_bar_clamps_to_nearest_group() {
    XCTAssertEqual(layout.drop(atX: -50, dragging: (1, 0)), BarDrop(group: 0, index: 0))
    XCTAssertEqual(layout.drop(atX: 999, dragging: (0, 0)), BarDrop(group: 1, index: 1))
  }

  func test_column_with_fixed_height_is_centred() {
    var strip = Strip()
    strip.append(1, width: 0.5)
    strip.columns[0].fixedHeight = 200
    let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)
    let frame = strip.layout(LayoutContext(geometry: geometry, displayFrame: geometry.viewport, otherDisplays: []))[1]!.frame
    XCTAssertEqual(frame.height, 200)
    XCTAssertEqual(frame.midY, 430, accuracy: 1)
  }

  func test_rubber_band_resists_drags_past_the_ends() {
    let layout = BarLayout(groupCounts: [3, 1], icon: 34, spacing: 6, groupGap: 25, padding: 8)
    let low = 8 + 17.0
    let high = layout.width - 8 - 17
    XCTAssertEqual(layout.rubberBand(100), 100)
    XCTAssertLessThan(layout.rubberBand(low - 500), low)
    XCTAssertGreaterThan(layout.rubberBand(low - 500), low - 34)
    XCTAssertGreaterThan(layout.rubberBand(high + 500), high)
    XCTAssertLessThan(layout.rubberBand(high + 500), high + 34)
    XCTAssertLessThan(layout.rubberBand(high + 10), layout.rubberBand(high + 50))
  }
}
