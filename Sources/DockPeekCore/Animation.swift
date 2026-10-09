import CoreGraphics

public let panelSize = 128.0
public let iconTop = 91.0
public let iconSize = 54.0
@Sendable public func restingY(edge: Double, fraction: Double) -> Double {
  edge - iconTop + iconSize * fraction
}
@Sendable public func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
public struct Pose: Sendable {
  public init(point: CGPoint, angle: Double = 0, squash: Double = 1) {
    self.point = point
    self.angle = angle
    self.squash = squash
  }
  public var point: CGPoint
  public var angle = 0.0
  public var squash = 1.0
}
@Sendable public func tumblePose(progress: Double, start: CGPoint, target: CGPoint, fromLeft: Bool)
  -> Pose
{
  let t = min(max(progress, 0), 1)
  let x = start.x + (target.x - start.x) * (1 - pow(1 - t, 1.5))
  var y = start.y
  var squash = 1.0
  // Three diminishing hops travel along the screen edge while both turns continue.
  let hops: [(Double, Double, Double)] = [(0, 0.42, 110), (0.42, 0.70, 58), (0.70, 0.88, 26)]
  if t < 0.88 {
    for (begin, end, height) in hops where t >= begin && t < end {
      let flight = (t - begin) / (end - begin)
      y += height * 4 * flight * (1 - flight)
      if begin > 0 && flight < 0.12 { squash = 1 - 0.18 * sin(.pi * flight / 0.12) }
    }
  } else {
    let landing = (t - 0.88) / 0.12
    y += (target.y - start.y) * ease(landing)
    if landing < 0.25 { squash = 1 - 0.18 * sin(.pi * landing / 0.25) }
  }
  return Pose(point: CGPoint(x: x, y: y), angle: (fromLeft ? -1 : 1) * 4 * .pi * t, squash: squash)
}
@Sendable public func entryStyle(badge: String, coveredBadge: String?, configured: String) -> String
{
  coveredBadge == badge ? "slide" : configured
}
