import XCTest
@testable import SpoolCore

final class SpanTests: XCTestCase {
  let tall = CGRect(x: 0, y: 30, width: 1000, height: 800)
  let short = CGRect(x: 1000, y: 300, width: 1000, height: 530)
  lazy var geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 2000, height: 800), innerGap: 10, outerGap: 10)

  func makeStrip(_ count: Int, width: Double = 0.25) -> Strip {
    var strip = Strip()
    for id in 1...count { strip.append(WindowID(id), width: width) }
    strip.focusedColumn = 0
    return strip
  }

  func context() -> LayoutContext {
    LayoutContext(
      geometry: geometry,
      displayFrame: CGRect(x: 0, y: 0, width: 2000, height: 830),
      otherDisplays: [],
      bands: [tall, short]
    )
  }

  func test_each_column_takes_the_height_of_the_screen_it_sits_on() {
    let placements = makeStrip(4).layout(context())
    XCTAssertEqual(placements[1]!.frame.minY, 40)
    XCTAssertEqual(placements[1]!.frame.height, 780)
    XCTAssertEqual(placements[3]!.frame.minY, 310)
    XCTAssertEqual(placements[3]!.frame.height, 510)
  }

  func test_straddle_detection() {
    let strip = makeStrip(6)
    XCTAssertFalse(strip.straddles(seams: [1000], at: 0, geometry))
    XCTAssertTrue(strip.straddles(seams: [1000], at: 100, geometry))
  }

  func test_seam_safe_snap_never_rests_a_window_on_the_seam() {
    let strip = makeStrip(6)
    for near in stride(from: 0.0, through: 900, by: 37) {
      let scroll = strip.seamSafeSnapScroll(near: near, seams: [1000], keepVisible: nil, geometry)
      XCTAssertFalse(strip.straddles(seams: [1000], at: scroll, geometry), "near \(near) gave \(scroll)")
      XCTAssertGreaterThanOrEqual(scroll, 0)
      XCTAssertLessThanOrEqual(scroll, strip.maxScroll(geometry) + 0.001)
    }
  }

  func test_seam_safe_snap_keeps_the_focused_column_visible() {
    let strip = makeStrip(6)
    let scroll = strip.seamSafeSnapScroll(near: 0, seams: [1000], keepVisible: 5, geometry)
    XCTAssertTrue(strip.fullyVisibleColumns(at: scroll, geometry).contains(5))
    XCTAssertFalse(strip.straddles(seams: [1000], at: scroll, geometry))
  }

  func test_without_seams_it_matches_plain_snap() {
    let strip = makeStrip(6)
    XCTAssertEqual(strip.seamSafeSnapScroll(near: 300, seams: [], keepVisible: nil, geometry), strip.snapScroll(near: 300, geometry), accuracy: 0.001)
  }
}
