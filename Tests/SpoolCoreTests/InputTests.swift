import XCTest
@testable import SpoolCore

final class InputTests: XCTestCase {
  let settings = ThumbWheelSettings()

  func test_thumb_wheel_scrolls_strip() {
    let route = ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0), settings: settings)
    XCTAssertEqual(route, .scrollStrip(by: -12))
  }

  func test_line_only_deltas_still_scroll() {
    let route = ScrollClassifier.route(ScrollSample(pointDeltaX: 0, pointDeltaY: 0, lineDeltaX: -1), settings: settings)
    XCTAssertEqual(route, .scrollStrip(by: 30))
  }

  func test_vertical_wheel_passes_through() {
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 0, pointDeltaY: 5), settings: settings), .passThrough)
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 3, pointDeltaY: 1), settings: settings), .passThrough)
  }

  func test_trackpad_and_momentum_pass_through() {
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0, scrollPhase: 2), settings: settings), .passThrough)
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0, momentumPhase: 2), settings: settings), .passThrough)
  }

  func test_passthrough_modifier_and_shift_pass_through() {
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0, modifiers: .option), settings: settings), .passThrough)
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0, modifiers: .shift), settings: settings), .passThrough)
  }

  func test_passthrough_app_passes_through() {
    let sample = ScrollSample(pointDeltaX: 4, pointDeltaY: 0, bundleIDUnderPointer: "com.microsoft.Excel")
    XCTAssertEqual(ScrollClassifier.route(sample, settings: settings), .passThrough)
  }

  func test_disabled_and_inverted() {
    var custom = settings
    custom.inverted = true
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0), settings: custom), .scrollStrip(by: 12))
    custom.enabled = false
    XCTAssertEqual(ScrollClassifier.route(ScrollSample(pointDeltaX: 4, pointDeltaY: 0), settings: custom), .passThrough)
  }

  func test_spring_settles_on_target() {
    var spring = Spring(position: 0, target: 500)
    for _ in 0..<120 { spring.step(1.0 / 60.0) }
    XCTAssertTrue(spring.isSettled)
    XCTAssertEqual(spring.position, 500)
  }

  func test_settings_decode_fills_missing_keys_with_defaults() throws {
    let json = #"{"innerGap": 4, "thumbWheel": {"speed": 7}}"#
    let decoded = try JSONDecoder().decode(SpoolSettings.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.innerGap, 4)
    XCTAssertEqual(decoded.thumbWheel.speed, 7)
    XCTAssertTrue(decoded.thumbWheel.enabled)
    XCTAssertEqual(decoded.outerGap, SpoolSettings().outerGap)
  }

  func test_default_shortcuts_have_no_duplicate_keys() {
    let keys = Shortcut.defaults.map { "\($0.keyCode)-\($0.modifiers.rawValue)" }
    XCTAssertEqual(keys.count, Set(keys).count)
  }
}
