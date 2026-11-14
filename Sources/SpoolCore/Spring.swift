import Foundation

public struct Spring: Equatable, Sendable {
  public var position: Double
  public var velocity = 0.0
  public var target: Double
  public var stiffness = 900.0
  public var damping = 2 * 30.0

  public init(position: Double, target: Double? = nil) {
    self.position = position
    self.target = target ?? position
  }

  public var isSettled: Bool {
    abs(target - position) < 0.5 && abs(velocity) < 5
  }

  public mutating func step(_ dt: Double) {
    let steps = max(1, Int((dt / (1.0 / 240.0)).rounded(.up)))
    let h = dt / Double(steps)
    for _ in 0..<steps {
      let force = stiffness * (target - position) - damping * velocity
      velocity += force * h
      position += velocity * h
    }
    if isSettled {
      position = target
      velocity = 0
    }
  }

  public mutating func setStiffness(_ value: Double) {
    stiffness = value
    damping = 2 * value.squareRoot()
  }

  public mutating func jump(to value: Double) {
    position = value
    target = value
    velocity = 0
  }
}
