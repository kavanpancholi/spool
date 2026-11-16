import CoreGraphics

public enum DisplayArrangement {
  public static func isolated(_ frames: [UInt32: CGRect], primary: UInt32) -> [UInt32: CGRect] {
    guard frames.count > 1, frames[primary] != nil, sharesRows(frames) else { return frames }
    return staircase(frames, primary: primary)
  }

  public static func isStaircase(_ frames: [UInt32: CGRect], primary: UInt32) -> Bool {
    frames.count > 1 && frames[primary] != nil && staircase(frames, primary: primary) == frames
  }

  public static func sharesRows(_ frames: [UInt32: CGRect]) -> Bool {
    let byTop = frames.values.sorted { $0.minY < $1.minY }
    return zip(byTop, byTop.dropFirst()).contains { $0.maxY > $1.minY }
  }

  private static func staircase(_ frames: [UInt32: CGRect], primary: UInt32) -> [UInt32: CGRect] {
    let order = frames.keys.sorted {
      let left = frames[$0]!, right = frames[$1]!
      return left.width == right.width ? $0 < $1 : left.width > right.width
    }
    var result: [UInt32: CGRect] = [:]
    var x = 0.0
    var y = 0.0
    for (index, id) in order.enumerated() {
      let size = frames[id]!.size
      if index > 0 { y -= size.height }
      result[id] = CGRect(origin: CGPoint(x: x, y: y), size: size)
      x += size.width
    }
    let anchor = result[primary]!.origin
    let target = frames[primary]!.origin
    return result.mapValues { $0.offsetBy(dx: target.x - anchor.x, dy: target.y - anchor.y) }
  }

  public static func pointerDestination(
    at location: CGPoint,
    delta: CGVector,
    technical: [UInt32: CGRect],
    desk: [UInt32: CGRect]
  ) -> CGPoint? {
    guard technical != desk, delta.dx != 0 || delta.dy != 0 else { return nil }
    let ids = technical.keys.sorted()
    func containing(_ point: CGPoint) -> UInt32? {
      ids.first { technical[$0]!.contains(point) }
    }
    let previous = CGPoint(x: location.x - delta.dx, y: location.y - delta.dy)
    guard let sourceID = containing(location) ?? containing(previous),
      let source = technical[sourceID], let sourceDesk = desk[sourceID]
    else { return nil }

    let edge = CGPoint(
      x: min(max(location.x, source.minX), source.maxX - 1),
      y: min(max(location.y, source.minY), source.maxY - 1)
    )
    let onDesk = CGPoint(x: edge.x - source.minX + sourceDesk.minX, y: edge.y - source.minY + sourceDesk.minY)
    let crossings: [(CGVector, Bool)] = [
      (CGVector(dx: -1, dy: 0), delta.dx < 0 && location.x <= source.minX + 1),
      (CGVector(dx: 1, dy: 0), delta.dx > 0 && location.x >= source.maxX - 2),
      (CGVector(dx: 0, dy: -1), delta.dy < 0 && location.y <= source.minY + 1),
      (CGVector(dx: 0, dy: 1), delta.dy > 0 && location.y >= source.maxY - 2),
    ]

    for (direction, crossing) in crossings where crossing {
      for id in ids where id != sourceID {
        guard let targetDesk = desk[id], let target = technical[id] else { continue }
        let touches: Bool
        var point = CGPoint(x: onDesk.x - targetDesk.minX, y: onDesk.y - targetDesk.minY)
        switch (direction.dx, direction.dy) {
        case (-1, _):
          touches = abs(targetDesk.maxX - sourceDesk.minX) <= 1 && (targetDesk.minY..<targetDesk.maxY).contains(onDesk.y)
          point.x = targetDesk.width - 3
        case (1, _):
          touches = abs(targetDesk.minX - sourceDesk.maxX) <= 1 && (targetDesk.minY..<targetDesk.maxY).contains(onDesk.y)
          point.x = 2
        case (_, -1):
          touches = abs(targetDesk.maxY - sourceDesk.minY) <= 1 && (targetDesk.minX..<targetDesk.maxX).contains(onDesk.x)
          point.y = targetDesk.height - 3
        default:
          touches = abs(targetDesk.minY - sourceDesk.maxY) <= 1 && (targetDesk.minX..<targetDesk.maxX).contains(onDesk.x)
          point.y = 2
        }
        guard touches else { continue }
        return CGPoint(x: target.minX + point.x, y: target.minY + point.y)
      }
    }
    return nil
  }
}
