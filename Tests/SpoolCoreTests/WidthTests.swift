import XCTest
@testable import SpoolCore

final class WidthTests: XCTestCase {
  let geometry = StripGeometry(viewport: CGRect(x: 0, y: 30, width: 1000, height: 800), innerGap: 10, outerGap: 10)

  func test_parses_percentages_points_and_bare_numbers() {
    XCTAssertEqual(WidthPreset(parsing: "40%"), .fraction(0.4))
    XCTAssertEqual(WidthPreset(parsing: " 50 "), .fraction(0.5))
    XCTAssertEqual(WidthPreset(parsing: "1200pt"), .points(1200))
    XCTAssertEqual(WidthPreset(parsing: "800 px"), .points(800))
    XCTAssertNil(WidthPreset(parsing: "5%"))
    XCTAssertNil(WidthPreset(parsing: "wide"))
    XCTAssertEqual(WidthPreset.parseList("33%, junk, 900pt"), [.fraction(0.33), .points(900)])
  }

  func test_old_settings_with_plain_fractions_still_decode() throws {
    let json = #"{"widthPresets":[0.25,0.75]}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(SpoolSettings.self, from: json)
    XCTAssertEqual(settings.widthPresets, [.fraction(0.25), .fraction(0.75)])
    XCTAssertNil(settings.defaultWidth)
  }

  func test_settings_round_trip_points_and_display_overrides() throws {
    var settings = SpoolSettings()
    settings.widthPresets = [.fraction(0.5), .points(1200)]
    settings.defaultWidth = .points(900)
    settings.displayWidths["A"] = DisplayWidths(presets: [.fraction(0.25)], defaultWidth: nil)
    let decoded = try JSONDecoder().decode(SpoolSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.widthPresets, settings.widthPresets)
    XCTAssertEqual(decoded.defaultWidth, .points(900))
    XCTAssertEqual(decoded.displayWidths, settings.displayWidths)
  }

  func test_a_display_override_replaces_only_what_it_sets() {
    var settings = SpoolSettings()
    settings.defaultWidth = .fraction(0.6)
    settings.displayWidths["A"] = DisplayWidths(presets: [.fraction(0.25)], defaultWidth: nil)
    XCTAssertEqual(settings.forDisplay("A").widthPresets, [.fraction(0.25)])
    XCTAssertEqual(settings.forDisplay("A").defaultWidth, .fraction(0.6))
    XCTAssertEqual(settings.forDisplay("B").widthPresets, settings.widthPresets)
  }

  func test_point_presets_convert_to_the_exact_width_on_screen() {
    XCTAssertEqual(geometry.points(forFraction: WidthPreset.points(485).fraction(in: geometry)), 485, accuracy: 0.001)
  }

  func test_cycle_width_walks_mixed_presets_in_size_order() {
    var settings = SpoolSettings()
    settings.widthPresets = [.points(485), .fraction(0.25)]
    var strip = Strip()
    strip.append(1, width: 0.1)
    strip.focusedColumn = 0
    _ = strip.apply(.cycleWidth, settings: settings, geometry: geometry)
    XCTAssertEqual(strip.columns[0].width, 0.25)
    _ = strip.apply(.cycleWidth, settings: settings, geometry: geometry)
    XCTAssertEqual(geometry.points(forFraction: strip.columns[0].width), 485, accuracy: 0.001)
  }

  func test_set_width_applies_points() {
    var strip = Strip()
    strip.append(1, width: 0.5)
    strip.focusedColumn = 0
    _ = strip.apply(.setWidth(.points(300)), settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(geometry.points(forFraction: strip.columns[0].width), 300, accuracy: 0.001)
  }

  func test_grow_fills_the_space_left_by_the_visible_columns() {
    var strip = Strip()
    strip.append(1, width: 0.3)
    strip.append(2, width: 0.3)
    strip.append(3, width: 0.9)
    strip.focusedColumn = 1
    let result = strip.apply(.growIntoFreeSpace, settings: SpoolSettings(), geometry: geometry)
    XCTAssertTrue(result.layoutChanged)
    let first = geometry.points(forFraction: 0.3)
    XCTAssertEqual(geometry.points(forFraction: strip.columns[1].width), geometry.usableWidth - first - 10, accuracy: 0.001)
    XCTAssertEqual(strip.scroll, 0)
  }

  func test_grow_does_nothing_when_the_visible_columns_already_fill_the_screen() {
    var strip = Strip()
    strip.append(1, width: 0.5)
    strip.append(2, width: 0.5)
    strip.focusedColumn = 0
    XCTAssertFalse(strip.apply(.growIntoFreeSpace, settings: SpoolSettings(), geometry: geometry).handled)
  }

  func test_grow_on_a_part_visible_column_makes_it_full_width() {
    var strip = Strip()
    strip.append(1, width: 0.8)
    strip.append(2, width: 0.5)
    strip.focusedColumn = 1
    _ = strip.apply(.growIntoFreeSpace, settings: SpoolSettings(), geometry: geometry)
    XCTAssertEqual(strip.columns[1].width, 1, accuracy: 0.0001)
  }
}
