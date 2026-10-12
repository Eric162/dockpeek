import CoreGraphics

public enum PresentationPhase: Sendable { case hidden, entering, shown, exiting }

/// The host owns deadlines and the final pose.
///
/// Configuration is captured per transition.
public struct PresentationMotion: Sendable {
  public private(set) var phase = PresentationPhase.hidden
  public var target: CGPoint = .zero
  public private(set) var screen: CGRect = .zero
  public private(set) var current = Pose(point: .zero)
  public var isAnimating: Bool { phase == .entering || phase == .exiting }
  private var plugin: (any AnimationPlugin)?
  private var context = AnimationContext(
    stage: .entry, finalFrame: .zero, screen: .zero, initial: Pose(point: .zero), badge: "")
  private var settings: [String: AnimationValue] = [:]
  private var began = 0.0
  private var duration = 0.0
  public init() {}

  public mutating func show(
    at target: CGPoint, screen: CGRect, animation: EntryAnimation, now: Double,
    configuration: Configuration = Configuration(),
    registry: AnimationRegistry = AnimationRegistry(),
    badge: String = ""
  ) {
    let interrupted = isAnimating
    self.target = target
    self.screen = screen
    phase = .entering
    context = makeContext(stage: .entry, badge: badge)
    begin(
      id: animation.rawValue, now: now, configuration: configuration, registry: registry,
      interrupted: interrupted)
  }
  public mutating func hide(
    animation: DismissAnimation, now: Double, configuration: Configuration = Configuration(),
    registry: AnimationRegistry = AnimationRegistry(), badge: String = ""
  ) {
    guard phase != .hidden, phase != .exiting else { return }
    phase = .exiting
    context = makeContext(stage: .dismissal, badge: badge)
    begin(
      id: animation.rawValue, now: now, configuration: configuration, registry: registry,
      interrupted: true)
  }
  private func makeContext(stage: AnimationStage, badge: String) -> AnimationContext {
    AnimationContext(
      stage: stage,
      finalFrame: CGRect(origin: target, size: CGSize(width: panelSize, height: panelSize)),
      screen: screen, initial: current, badge: badge)
  }
  private mutating func begin(
    id: String, now: Double, configuration: Configuration,
    registry: AnimationRegistry, interrupted: Bool
  ) {
    began = now
    let stage = context.stage
    plugin = registry.plugin(id: id, stage: stage)
    if !interrupted, let plugin {
      context = AnimationContext(
        stage: stage, finalFrame: context.finalFrame, screen: screen,
        initial: plugin.start(in: context), badge: context.badge)
    }
    settings = plugin?.descriptor.resolved(configuration.settings(for: id, stage: stage)) ?? [:]
    duration = min(settings["duration"]?.number ?? 0, AnimationRegistry.maximumDuration)
    current = context.initial
  }
  public mutating func step(now: Double) -> Pose? {
    switch phase {
    case .hidden: return nil
    case .shown: current = Pose(point: target)
    case .entering, .exiting:
      let elapsed = max(now - began, 0)
      if let plugin, duration > 0, elapsed < duration, elapsed < AnimationRegistry.maximumDuration {
        let pose = plugin.frame(in: context, progress: elapsed / duration, settings: settings)
        if valid(pose) { current = pose } else { finish() }
      } else {
        finish()
      }
    }
    return phase == .hidden ? nil : current
  }
  private mutating func finish() {
    phase = phase == .entering ? .shown : .hidden
    current = Pose(point: target)
    plugin = nil
    settings.removeAll()
  }
  private func valid(_ pose: Pose) -> Bool {
    let bounds = screen.insetBy(dx: -4 * panelSize, dy: -4 * panelSize)
    return pose.point.x.isFinite && pose.point.y.isFinite && bounds.contains(pose.point)
      && pose.angle.isFinite && abs(pose.angle) <= 100 * .pi
      && pose.squash.isFinite && (0.1...4).contains(pose.squash)
      && pose.opacity.isFinite && (0...1).contains(pose.opacity)
  }
}
