import CoreGraphics
import Foundation

public struct WindowTraits: Equatable, Sendable {
  public var role: String?
  public var subrole: String?
  public var identifier: String?
  public var hasCloseButton: Bool
  public var hasMinimizeButton: Bool
  public var isResizable: Bool
  public var isMovable: Bool
  public var isMinimized: Bool
  public var isFullScreen: Bool
  public var size: CGSize?

  public init(
    role: String?,
    subrole: String?,
    identifier: String?,
    hasCloseButton: Bool,
    hasMinimizeButton: Bool,
    isResizable: Bool,
    isMovable: Bool,
    isMinimized: Bool,
    isFullScreen: Bool,
    size: CGSize?
  ) {
    self.role = role
    self.subrole = subrole
    self.identifier = identifier
    self.hasCloseButton = hasCloseButton
    self.hasMinimizeButton = hasMinimizeButton
    self.isResizable = isResizable
    self.isMovable = isMovable
    self.isMinimized = isMinimized
    self.isFullScreen = isFullScreen
    self.size = size
  }
}

public enum WindowDecision: Equatable, Sendable {
  case tile
  case float
  case notYet
}

public enum WindowRules {
  static let panelIdentifiers: Set<String> = ["open-panel", "save-panel"]

  public static func decide(_ traits: WindowTraits) -> WindowDecision {
    guard let role = traits.role, let subrole = traits.subrole, let size = traits.size else { return .notYet }
    guard role == "AXWindow", subrole == "AXStandardWindow" else { return .float }
    if let identifier = traits.identifier, panelIdentifiers.contains(identifier) { return .float }
    guard traits.hasCloseButton || traits.hasMinimizeButton else { return .float }
    guard !traits.isMinimized, !traits.isFullScreen else { return .float }
    guard traits.isResizable, traits.isMovable else { return .float }
    guard size.width >= 80, size.height >= 60 else { return .float }
    return .tile
  }
}
