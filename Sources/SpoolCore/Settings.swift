import Foundation

public enum CenterMode: String, Codable, CaseIterable, Sendable {
  case never
  case onOverflow
  case always
}

public enum ModifierKey: String, Codable, CaseIterable, Sendable {
  case none
  case option
  case command
  case control
  case shift
}

public struct ThumbWheelSettings: Codable, Equatable, Sendable {
  public var enabled = true
  public var speed = 3.0
  public var inverted = false
  public var passthroughModifier = ModifierKey.option
  public var passthroughBundleIDs = [
    "com.microsoft.Excel",
    "com.apple.iWork.Numbers",
    "com.figma.Desktop",
  ]
  public var snapToColumns = true
  public var snapDelay = 0.45

  public init() {}

  public init(from decoder: Decoder) throws {
    let defaults = ThumbWheelSettings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
    speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? defaults.speed
    inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? defaults.inverted
    passthroughModifier = try c.decodeIfPresent(ModifierKey.self, forKey: .passthroughModifier) ?? defaults.passthroughModifier
    passthroughBundleIDs = try c.decodeIfPresent([String].self, forKey: .passthroughBundleIDs) ?? defaults.passthroughBundleIDs
    snapToColumns = try c.decodeIfPresent(Bool.self, forKey: .snapToColumns) ?? defaults.snapToColumns
    snapDelay = try c.decodeIfPresent(Double.self, forKey: .snapDelay) ?? defaults.snapDelay
  }
}

public struct TrackpadSettings: Codable, Equatable, Sendable {
  public var fingers = 3
  public var speed = 1.0
  public var inverted = false

  public init() {}

  public init(from decoder: Decoder) throws {
    let defaults = TrackpadSettings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    fingers = try c.decodeIfPresent(Int.self, forKey: .fingers) ?? defaults.fingers
    speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? defaults.speed
    inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? defaults.inverted
  }
}

public struct SpoolSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 2

  public var version = SpoolSettings.currentVersion
  public var enabled = true
  public var innerGap = 8.0
  public var outerGap = 8.0
  public var widthPresets = [1.0 / 3.0, 0.5, 2.0 / 3.0]
  public var widthStep = 0.1
  public var centerMode = CenterMode.never
  public var animate = true
  public var showBar = true
  public var smoothSlides = true
  public var thumbWheel = ThumbWheelSettings()
  public var trackpad = TrackpadSettings()
  public var floatingBundleIDs: [String] = []
  public var excludedDisplayIDs: [String] = []

  public init() {}

  public init(from decoder: Decoder) throws {
    let defaults = SpoolSettings()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
    innerGap = try c.decodeIfPresent(Double.self, forKey: .innerGap) ?? defaults.innerGap
    outerGap = try c.decodeIfPresent(Double.self, forKey: .outerGap) ?? defaults.outerGap
    widthPresets = try c.decodeIfPresent([Double].self, forKey: .widthPresets) ?? defaults.widthPresets
    widthStep = try c.decodeIfPresent(Double.self, forKey: .widthStep) ?? defaults.widthStep
    centerMode = try c.decodeIfPresent(CenterMode.self, forKey: .centerMode) ?? defaults.centerMode
    animate = try c.decodeIfPresent(Bool.self, forKey: .animate) ?? defaults.animate
    showBar = try c.decodeIfPresent(Bool.self, forKey: .showBar) ?? defaults.showBar
    smoothSlides = try c.decodeIfPresent(Bool.self, forKey: .smoothSlides) ?? defaults.smoothSlides
    thumbWheel = try c.decodeIfPresent(ThumbWheelSettings.self, forKey: .thumbWheel) ?? defaults.thumbWheel
    trackpad = try c.decodeIfPresent(TrackpadSettings.self, forKey: .trackpad) ?? defaults.trackpad
    floatingBundleIDs = try c.decodeIfPresent([String].self, forKey: .floatingBundleIDs) ?? defaults.floatingBundleIDs
    excludedDisplayIDs = try c.decodeIfPresent([String].self, forKey: .excludedDisplayIDs) ?? defaults.excludedDisplayIDs
    let savedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    if savedVersion < 2 {
      thumbWheel.snapDelay = max(thumbWheel.snapDelay, defaults.thumbWheel.snapDelay)
    }
    version = Self.currentVersion
  }

  public var sanitizedWidthPresets: [Double] {
    let valid = widthPresets.filter { $0 > 0.05 && $0 <= 1.0 }.sorted()
    return valid.isEmpty ? [0.5] : valid
  }
}
