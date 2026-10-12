import CoreGraphics

func durationSetting(defaultValue: Double) -> AnimationSetting {
  AnimationSetting(
    id: "duration", name: "Duration (seconds)", kind: .number,
    defaultValue: .number(defaultValue), minimum: 0.05,
    maximum: AnimationRegistry.maximumDuration, choices: nil)
}

public struct SlideAnimation: AnimationPlugin {
  public let descriptor = AnimationDescriptor(
    id: "slide", name: "Slide", stages: [.entry, .dismissal],
    settings: [durationSetting(defaultValue: 0.35)])
  public init() {}
  public func start(in context: AnimationContext) -> Pose {
    context.stage == .entry
      ? Pose(
        point: CGPoint(
          x: context.finalFrame.minX, y: context.screen.minY - context.finalFrame.height - 4))
      : context.initial
  }
  public func frame(
    in context: AnimationContext, progress: Double, settings: [String: AnimationValue]
  ) -> Pose {
    let t = ease(progress)
    return Pose(
      point: CGPoint(
        x: context.initial.point.x + (context.destination.x - context.initial.point.x) * t,
        y: context.initial.point.y + (context.destination.y - context.initial.point.y) * t),
      angle: context.initial.angle * (1 - t),
      squash: context.initial.squash + (1 - context.initial.squash) * t,
      opacity: context.initial.opacity + (1 - context.initial.opacity) * t)
  }
}

public struct TumbleAnimation: AnimationPlugin {
  public let descriptor = AnimationDescriptor(
    id: "tumble", name: "Tumble", stages: [.entry],
    settings: [durationSetting(defaultValue: 1.4)])
  public init() {}
  public func start(in context: AnimationContext) -> Pose {
    Pose(
      point: CGPoint(
        x: context.fromLeft ? context.screen.minX - context.finalFrame.width : context.screen.maxX,
        y: context.screen.minY - 37))
  }
  public func frame(
    in context: AnimationContext, progress: Double, settings: [String: AnimationValue]
  ) -> Pose {
    tumblePose(
      progress: progress, start: context.initial.point, target: context.destination,
      fromLeft: context.fromLeft)
  }
}
