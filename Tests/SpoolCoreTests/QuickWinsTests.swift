import XCTest
@testable import SpoolCore

final class QuickWinsTests: XCTestCase {
  func test_previous_skips_the_current_and_closed_windows() {
    var history = FocusHistory()
    [1, 2, 3, 2].forEach { history.record($0) }
    XCTAssertEqual(history.windows, [1, 3, 2])
    XCTAssertEqual(history.previous(current: 2) { _ in true }, 3)
    XCTAssertEqual(history.previous(current: 2) { $0 != 3 }, 1)
    history.forget(3)
    XCTAssertEqual(history.previous(current: 2) { _ in true }, 1)
  }

  func test_history_keeps_only_the_latest_windows() {
    var history = FocusHistory(limit: 3)
    (1...5).forEach { history.record(WindowID($0)) }
    XCTAssertEqual(history.windows, [3, 4, 5])
  }

  func test_previous_window_shortcut_is_control_option_tab() {
    XCTAssertTrue(Shortcut.defaults.contains(Shortcut(KeyCode.tab, [.control, .option], .focusPrevious)))
  }

  func test_cheatsheet_merges_keys_and_folds_window_numbers() {
    let entries = Shortcut.cheatsheet(Shortcut.defaults)
    let left = entries.first { $0.title == Command.focus(.left).title }
    XCTAssertEqual(left?.keys, ["⌃⌥H", "⌃⌥←"])
    XCTAssertEqual(entries.filter { $0.title.hasPrefix("Focus window") }.count, 1)
    XCTAssertEqual(entries.first { $0.title == "Focus window 1 to 9" }?.keys, ["⌃⌥1…9"])
    XCTAssertEqual(Set(entries.map(\.title)).count, entries.count)
  }

  func test_new_settings_decode_from_old_files() throws {
    let settings = try JSONDecoder().decode(SpoolSettings.self, from: Data("{\"version\": 3}".utf8))
    XCTAssertTrue(settings.focusBorder)
    XCTAssertFalse(settings.dimInactive)
    XCTAssertTrue(settings.cheatsheetOnHold)
  }
}
