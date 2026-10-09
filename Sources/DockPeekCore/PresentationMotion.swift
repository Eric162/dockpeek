import CoreGraphics

public enum PresentationPhase: Sendable {
  case hidden, entering, shown, exiting
}

/// Animation state with an injected monotonic clock; no windows or timers.
public struct PresentationMotion: Sendable {
  public private(set) var phase = PresentationPhase.hidden
  public var target: CGPoint = .zero
  public private(set) var screen: CGRect = .zero
  private var start: CGPoint = .zero
  private var began = 0.0
  private var entry = EntryAnimation.slide
  private var dismissal = DismissAnimation.slide
  private var fromLeft = true
  public private(set) var current = Pose(point: .zero)
  public var isAnimating: Bool { phase == .entering || phase == .exiting }

  public init() {}

  public mutating func show(
    at target: CGPoint, screen: CGRect, animation: EntryAnimation, now: Double
  ) {
    self.target = target
    self.screen = screen
    entry = animation
    fromLeft = target.x + 64 - screen.minX <= screen.maxX - target.x - 64
    phase = .entering
    began = now
    start =
      animation == .tumble
      ? CGPoint(x: fromLeft ? screen.minX - panelSize : screen.maxX, y: screen.minY - 37)
      : CGPoint(x: target.x, y: screen.minY - panelSize - 4)
    if animation == .none { start = target }
    current = Pose(point: start)
  }

  public mutating func hide(animation: DismissAnimation, now: Double) {
    guard phase != .hidden, phase != .exiting else { return }
    phase = .exiting
    began = now
    start = current.point
    dismissal = animation
  }

  public mutating func step(now: Double, configuration: Configuration) -> Pose? {
    switch phase {
    case .hidden: return nil
    case .shown: current = Pose(point: target)
    case .entering: enter(now: now, configuration: configuration)
    case .exiting:
      let t = min(max((now - began) / configuration.dismissDuration, 0), 1)
      current = Pose(
        point: CGPoint(
          x: start.x, y: start.y + (screen.minY - panelSize - 4 - start.y) * ease(t)))
      if t >= 1 || dismissal == .none {
        phase = .hidden
        return nil
      }
    }
    return current
  }

  private mutating func enter(now: Double, configuration: Configuration) {
    let duration = entry == .tumble ? configuration.tumbleDuration : configuration.slideDuration
    let t = min(max((now - began) / duration, 0), 1)
    switch entry {
    case .tumble:
      current = tumblePose(progress: t, start: start, target: target, fromLeft: fromLeft)
    case .slide:
      current = Pose(point: CGPoint(x: target.x, y: start.y + (target.y - start.y) * ease(t)))
    case .none: current = Pose(point: target)
    }
    if t >= 1 || entry == .none {
      phase = .shown
      current = Pose(point: target)
    }
  }
}
