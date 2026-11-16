import XCTest
@testable import SpoolCore

final class DragDropTests: XCTestCase {
  let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1010, height: 800), innerGap: 10, outerGap: 0)

  func strip() -> Strip {
    var strip = Strip()
    for id in 1...4 { strip.append(WindowID(id), width: 0.25) }
    strip.focusedColumn = 0
    return strip
  }

  func test_dropping_between_columns_moves_the_window_there() {
    var strip = strip()
    XCTAssertTrue(strip.drop(1, atScreenX: 505, geometry))
    XCTAssertEqual(strip.columns.map(\.windows), [[2], [3], [1], [4]])
    XCTAssertEqual(strip.focusedWindow, 1)
  }

  func test_dropping_on_the_middle_of_a_column_stacks_it() {
    var strip = strip()
    XCTAssertTrue(strip.drop(1, atScreenX: 375, geometry))
    XCTAssertEqual(strip.columns.map(\.windows), [[2], [3, 1], [4]])
    XCTAssertEqual(strip.focusedWindow, 1)
  }

  func test_dropping_a_stacked_window_between_columns_takes_it_out() {
    var strip = strip()
    _ = strip.drop(1, atScreenX: 375, geometry)
    XCTAssertTrue(strip.drop(1, atScreenX: 0, geometry))
    XCTAssertEqual(strip.columns.map(\.windows), [[1], [2], [3], [4]])
    XCTAssertEqual(strip.columns[0].width, 0.25)
  }

  func test_dropping_back_in_place_keeps_the_order() {
    var strip = strip()
    _ = strip.drop(2, atScreenX: 250, geometry)
    XCTAssertEqual(strip.columns.map(\.windows), [[1], [2], [3], [4]])
    XCTAssertEqual(strip.focusedWindow, 2)
  }
}
