import Foundation

public enum WidthPreset: Hashable, Codable, Sendable {
  case fraction(Double)
  case points(Double)

  public init?(parsing text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
    for suffix in ["pt", "px"] where trimmed.hasSuffix(suffix) {
      guard let value = Double(trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)),
        value >= 100, value <= 10000
      else { return nil }
      self = .points(value)
      return
    }
    let number = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
    guard let value = Double(number.trimmingCharacters(in: .whitespaces)), value >= 10, value <= 100 else { return nil }
    self = .fraction(value / 100)
  }

  public static func parseList(_ text: String) -> [WidthPreset] {
    text.split(separator: ",").compactMap { WidthPreset(parsing: String($0)) }
  }

  public var label: String {
    switch self {
    case .fraction(let value): "\(Int((value * 100).rounded()))%"
    case .points(let value): "\(Int(value.rounded()))pt"
    }
  }

  public func fraction(in geometry: StripGeometry) -> Double {
    switch self {
    case .fraction(let value): min(1, max(0.05, value))
    case .points(let value): geometry.fraction(forPoints: value)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Double.self) {
      self = .fraction(number)
    } else if let parsed = WidthPreset(parsing: try container.decode(String.self)) {
      self = parsed
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Width must look like 50% or 1200pt")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(label)
  }
}

public struct DisplayWidths: Codable, Equatable, Sendable {
  public var presets: [WidthPreset]?
  public var defaultWidth: WidthPreset?

  public init(presets: [WidthPreset]? = nil, defaultWidth: WidthPreset? = nil) {
    self.presets = presets
    self.defaultWidth = defaultWidth
  }

  public var isEmpty: Bool { presets == nil && defaultWidth == nil }
}
