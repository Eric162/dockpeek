import CoreGraphics

public enum BuiltinAnimation: String, AnimationPlugin {
  case slide, tumble
  public var descriptor: AnimationDescriptor {
    AnimationDescriptor(
      id: rawValue, name: rawValue.capitalized,
      stages: self == .slide ? [.entry, .dismissal] : [.entry],
      settings: [
        AnimationSetting(
          id: "duration", name: "Duration (seconds)", kind: .number,
          defaultValue: .number(self == .slide ? 0.35 : 1.4), minimum: 0.05,
          maximum: AnimationRegistry.maximumDuration, choices: nil)
      ])
  }
  public func start(in context: AnimationContext) -> Pose {
    guard context.stage == .entry else { return context.initial }
    return self == .slide
      ? Pose(
        point: CGPoint(
          x: context.finalFrame.minX, y: context.screen.minY - context.finalFrame.height - 4))
      : Pose(
        point: CGPoint(
          x: context.fromLeft
            ? context.screen.minX - context.finalFrame.width : context.screen.maxX,
          y: context.screen.minY - 37))
  }
  public func frame(
    in context: AnimationContext, progress: Double, settings: [String: AnimationValue]
  ) -> Pose {
    self == .slide
      ? context.initial.interpolated(to: Pose(point: context.destination), progress: ease(progress))
      : tumblePose(
        progress: progress, start: context.initial.point, target: context.destination,
        fromLeft: context.fromLeft)
  }
}
