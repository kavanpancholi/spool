import XCTest
@testable import SpoolCore

final class WindowRulesTests: XCTestCase {
  func traits(_ change: (inout WindowTraits) -> Void = { _ in }) -> WindowTraits {
    var traits = WindowTraits(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      identifier: nil,
      hasCloseButton: true,
      hasMinimizeButton: true,
      isResizable: true,
      isMovable: true,
      isMinimized: false,
      isFullScreen: false,
      size: CGSize(width: 800, height: 600)
    )
    change(&traits)
    return traits
  }

  func test_normal_window_tiles() {
    XCTAssertEqual(WindowRules.decide(traits()), .tile)
  }

  func test_open_and_save_panels_float() {
    XCTAssertEqual(WindowRules.decide(traits { $0.identifier = "open-panel" }), .float)
    XCTAssertEqual(WindowRules.decide(traits { $0.identifier = "save-panel" }), .float)
  }

  func test_window_without_close_or_minimize_floats() {
    XCTAssertEqual(WindowRules.decide(traits { $0.hasCloseButton = false; $0.hasMinimizeButton = false }), .float)
    XCTAssertEqual(WindowRules.decide(traits { $0.hasMinimizeButton = false }), .tile)
  }

  func test_dialogs_fixed_size_and_tiny_windows_float() {
    XCTAssertEqual(WindowRules.decide(traits { $0.subrole = "AXDialog" }), .float)
    XCTAssertEqual(WindowRules.decide(traits { $0.isResizable = false }), .float)
    XCTAssertEqual(WindowRules.decide(traits { $0.size = CGSize(width: 50, height: 600) }), .float)
  }

  func test_minimized_and_full_screen_are_left_alone() {
    XCTAssertEqual(WindowRules.decide(traits { $0.isMinimized = true }), .float)
    XCTAssertEqual(WindowRules.decide(traits { $0.isFullScreen = true }), .float)
  }

  func test_missing_role_means_not_ready_yet() {
    XCTAssertEqual(WindowRules.decide(traits { $0.subrole = nil }), .notYet)
  }
}
