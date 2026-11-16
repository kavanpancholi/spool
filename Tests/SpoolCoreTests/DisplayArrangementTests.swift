import CoreGraphics
import XCTest
@testable import SpoolCore

final class DisplayArrangementTests: XCTestCase {
  let lg: UInt32 = 1
  let macbook: UInt32 = 2
  lazy var desk: [UInt32: CGRect] = [
    lg: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    macbook: CGRect(x: 2560, y: 300, width: 1512, height: 982),
  ]

  func test_side_by_side_displays_become_a_staircase_anchored_on_the_primary() {
    let technical = DisplayArrangement.isolated(desk, primary: lg)
    XCTAssertEqual(technical[lg], desk[lg])
    XCTAssertEqual(technical[macbook], CGRect(x: 2560, y: -982, width: 1512, height: 982))
    XCTAssertFalse(DisplayArrangement.sharesRows(technical))
    XCTAssertTrue(DisplayArrangement.isStaircase(technical, primary: lg))
  }

  func test_primary_keeps_its_origin_when_it_is_the_narrower_display() {
    let technical = DisplayArrangement.isolated(desk, primary: macbook)
    XCTAssertEqual(technical[macbook]?.origin, desk[macbook]?.origin)
    XCTAssertEqual(technical[lg]?.maxX, technical[macbook]?.minX)
    XCTAssertEqual(technical[lg]?.minY, technical[macbook]?.maxY)
  }

  func test_stacked_displays_stay_as_they_are() {
    let stacked: [UInt32: CGRect] = [
      lg: CGRect(x: 0, y: 0, width: 2560, height: 1440),
      macbook: CGRect(x: 500, y: 1440, width: 1512, height: 982),
    ]
    XCTAssertEqual(DisplayArrangement.isolated(stacked, primary: lg), stacked)
    XCTAssertEqual(DisplayArrangement.isolated([lg: desk[lg]!], primary: lg), [lg: desk[lg]!])
  }

  func test_pointer_crosses_the_real_edge_at_the_same_height() {
    let technical = DisplayArrangement.isolated(desk, primary: lg)
    let point = DisplayArrangement.pointerDestination(
      at: CGPoint(x: 2559, y: 800), delta: CGVector(dx: 4, dy: 0), technical: technical, desk: desk
    )
    XCTAssertEqual(point, CGPoint(x: 2562, y: -982 + 500))
  }

  func test_pointer_crosses_back_to_the_left() {
    let technical = DisplayArrangement.isolated(desk, primary: lg)
    let point = DisplayArrangement.pointerDestination(
      at: CGPoint(x: 2560, y: -982 + 100), delta: CGVector(dx: -3, dy: 0), technical: technical, desk: desk
    )
    XCTAssertEqual(point, CGPoint(x: 2557, y: 400))
  }

  func test_pointer_does_not_warp_where_the_desk_has_no_neighbour() {
    let technical = DisplayArrangement.isolated(desk, primary: lg)
    XCTAssertNil(DisplayArrangement.pointerDestination(
      at: CGPoint(x: 2559, y: 100), delta: CGVector(dx: 4, dy: 0), technical: technical, desk: desk
    ))
    XCTAssertNil(DisplayArrangement.pointerDestination(
      at: CGPoint(x: 1200, y: 800), delta: CGVector(dx: 4, dy: 0), technical: technical, desk: desk
    ))
  }

  func test_no_warps_when_the_arrangement_is_the_desk() {
    XCTAssertNil(DisplayArrangement.pointerDestination(
      at: CGPoint(x: 2559, y: 800), delta: CGVector(dx: 4, dy: 0), technical: desk, desk: desk
    ))
  }
}
