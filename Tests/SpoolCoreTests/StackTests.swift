import XCTest
@testable import SpoolCore

final class StackTests: XCTestCase {
  let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)
  let settings = SpoolSettings()

  func strip(_ widths: [Double] = [0.5, 0.3, 0.4]) -> Strip {
    var strip = Strip()
    for (offset, width) in widths.enumerated() { strip.append(WindowID(offset + 1), width: width) }
    strip.focusedColumn = 1
    return strip
  }

  func test_a_lone_window_joins_the_column_on_its_left() {
    var strip = strip()
    XCTAssertTrue(strip.apply(.consumeOrExpel(.left), settings: settings, geometry: geometry).layoutChanged)
    XCTAssertEqual(strip.columns.map(\.windows), [[1, 2], [3]])
    XCTAssertEqual(strip.columns[0].width, 0.5)
    XCTAssertEqual(strip.focusedWindow, 2)
  }

  func test_a_lone_window_joins_the_column_on_its_right() {
    var strip = strip()
    _ = strip.apply(.consumeOrExpel(.right), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns.map(\.windows), [[1], [3, 2]])
    XCTAssertEqual(strip.focusedWindow, 2)
  }

  func test_a_stacked_window_leaves_as_its_own_column_with_the_stack_width() {
    var strip = strip()
    _ = strip.apply(.consumeOrExpel(.left), settings: settings, geometry: geometry)
    _ = strip.apply(.consumeOrExpel(.right), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns.map(\.windows), [[1], [2], [3]])
    XCTAssertEqual(strip.columns[1].width, 0.5)
    XCTAssertEqual(strip.focusedWindow, 2)
  }

  func test_nothing_to_join_at_the_strip_end() {
    var strip = strip()
    strip.focusedColumn = 0
    XCTAssertFalse(strip.apply(.consumeOrExpel(.left), settings: settings, geometry: geometry).handled)
    XCTAssertEqual(strip.columns.count, 3)
  }

  func test_prompt_columns_never_stack() {
    var strip = strip()
    strip.columns[0].fixedHeight = 200
    XCTAssertFalse(strip.consumeOrExpel(.left))
  }

  func test_move_up_and_down_inside_a_stack() {
    var strip = strip()
    _ = strip.apply(.consumeOrExpel(.left), settings: settings, geometry: geometry)
    _ = strip.apply(.move(.up), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].windows, [2, 1])
    XCTAssertEqual(strip.focusedWindow, 2)
    _ = strip.apply(.move(.down), settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].windows, [1, 2])
  }

  func test_a_stack_splits_the_height_evenly() {
    var strip = strip()
    _ = strip.apply(.consumeOrExpel(.left), settings: settings, geometry: geometry)
    let placements = strip.layout(LayoutContext(geometry: geometry, displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 830), otherDisplays: []))
    let top = placements[1]!.frame
    let bottom = placements[2]!.frame
    XCTAssertEqual(top.height, bottom.height)
    XCTAssertEqual(bottom.minY - top.maxY, 10)
    XCTAssertEqual(top.minX, bottom.minX)
  }
}
