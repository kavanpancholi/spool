import Foundation

public struct ModifierState: OptionSet, Hashable, Codable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let shift = ModifierState(rawValue: 1 << 0)
  public static let control = ModifierState(rawValue: 1 << 1)
  public static let option = ModifierState(rawValue: 1 << 2)
  public static let command = ModifierState(rawValue: 1 << 3)

  public func includes(_ key: ModifierKey) -> Bool {
    switch key {
    case .none: false
    case .option: contains(ModifierState.option)
    case .command: contains(ModifierState.command)
    case .control: contains(ModifierState.control)
    case .shift: contains(ModifierState.shift)
    }
  }
}

public struct ScrollSample: Equatable, Sendable {
  public var pointDeltaX: Double
  public var pointDeltaY: Double
  public var lineDeltaX: Double
  public var lineDeltaY: Double
  public var scrollPhase: Int
  public var momentumPhase: Int
  public var modifiers: ModifierState
  public var bundleIDUnderPointer: String?

  public init(
    pointDeltaX: Double,
    pointDeltaY: Double,
    lineDeltaX: Double = 0,
    lineDeltaY: Double = 0,
    scrollPhase: Int = 0,
    momentumPhase: Int = 0,
    modifiers: ModifierState = [],
    bundleIDUnderPointer: String? = nil
  ) {
    self.pointDeltaX = pointDeltaX
    self.pointDeltaY = pointDeltaY
    self.lineDeltaX = lineDeltaX
    self.lineDeltaY = lineDeltaY
    self.scrollPhase = scrollPhase
    self.momentumPhase = momentumPhase
    self.modifiers = modifiers
    self.bundleIDUnderPointer = bundleIDUnderPointer
  }
}

public enum ScrollRoute: Equatable, Sendable {
  case passThrough
  case scrollStrip(by: Double)
}

public enum ScrollClassifier {
  static let lineToPoints = 10.0

  public static func route(_ sample: ScrollSample, settings: ThumbWheelSettings) -> ScrollRoute {
    guard settings.enabled else { return .passThrough }
    guard sample.scrollPhase == 0, sample.momentumPhase == 0 else { return .passThrough }
    guard sample.pointDeltaY == 0, sample.lineDeltaY == 0 else { return .passThrough }
    guard !sample.modifiers.contains(.shift) else { return .passThrough }
    guard !sample.modifiers.includes(settings.passthroughModifier) else { return .passThrough }
    if let bundleID = sample.bundleIDUnderPointer, settings.passthroughBundleIDs.contains(bundleID) {
      return .passThrough
    }

    let raw = sample.pointDeltaX != 0 ? sample.pointDeltaX : sample.lineDeltaX * lineToPoints
    guard raw != 0 else { return .passThrough }
    let delta = -raw * settings.speed * (settings.inverted ? -1 : 1)
    return .scrollStrip(by: delta)
  }
}
