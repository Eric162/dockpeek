import CoreGraphics
import Foundation

/// A flat binding avoids arbitrary code and unbounded expression evaluation.
public struct AnimationScalar: Codable, Sendable {
  public let value: Double
  public let binding: String?
  public let multiplier: Double
  public let choices: [String: Double]?

  public init(
    value: Double = 0, binding: String? = nil, multiplier: Double = 1,
    choices: [String: Double]? = nil
  ) {
    self.value = value
    self.binding = binding
    self.multiplier = multiplier
    self.choices = choices
  }
  private enum CodingKeys: String, CodingKey { case value, binding, multiplier, choices }
  public init(from decoder: Decoder) throws {
    if let number = try? decoder.singleValueContainer().decode(Double.self) {
      self.init(value: number)
      return
    }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      value: try values.decodeIfPresent(Double.self, forKey: .value) ?? 0,
      binding: try values.decodeIfPresent(String.self, forKey: .binding),
      multiplier: try values.decodeIfPresent(Double.self, forKey: .multiplier) ?? 1,
      choices: try values.decodeIfPresent([String: Double].self, forKey: .choices))
  }
  public func encode(to encoder: Encoder) throws {
    if binding == nil && choices == nil {
      var values = encoder.singleValueContainer()
      try values.encode(value)
    } else {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(value, forKey: .value)
      try values.encodeIfPresent(binding, forKey: .binding)
      try values.encode(multiplier, forKey: .multiplier)
      try values.encodeIfPresent(choices, forKey: .choices)
    }
  }
  func isValid(settings: [AnimationSetting]) -> Bool {
    guard value.isFinite, abs(value) <= 10_000, multiplier.isFinite, abs(multiplier) <= 10_000,
      choices?.values.allSatisfy({ $0.isFinite && abs($0) <= 10_000 }) != false,
      (choices?.count ?? 0) <= 16
    else { return false }
    guard let binding else { return choices == nil }
    if Self.contextBindings.contains(binding) { return choices == nil }
    guard let setting = settings.first(where: { "setting.\($0.id)" == binding }) else {
      return false
    }
    if setting.kind == .choice {
      guard let choices, let allowed = setting.choices else { return false }
      return Set(choices.keys) == Set(allowed)
    }
    return choices == nil
  }
  private static let contextBindings: Set<String> = [
    "width", "height", "screenTopOffset", "unreadCount", "hasUnread", "direction", "entering",
  ]
  func resolve(in context: AnimationContext, settings: [String: AnimationValue]) -> Double {
    let input: Double
    switch binding {
    case "width": input = context.finalFrame.width
    case "height": input = context.finalFrame.height
    case "screenTopOffset": input = context.screen.maxY - context.finalFrame.minY
    case "unreadCount": input = Double(context.unreadCount ?? 0)
    case "hasUnread": input = context.hasUnread ? 1 : 0
    case "entering": input = context.stage == .entry ? 1 : 0
    case "direction": input = context.fromLeft ? -1 : 1
    default:
      switch settings[String((binding ?? "").dropFirst(8))] {
      case .number(let number): input = number
      case .toggle(let toggle): input = toggle ? 1 : 0
      case .choice(let choice): input = choices?[choice] ?? 0
      case nil: input = 0
      }
    }
    return value + input * multiplier
  }
}

public struct AnimationKeyframe: Codable, Sendable {
  public enum Curve: String, Codable, Sendable { case linear, easeOut, easeInOut }
  public let time: Double
  public let curve: Curve
  public let travel: AnimationScalar
  public let x: AnimationScalar
  public let y: AnimationScalar
  public let angle: AnimationScalar
  public let squash: AnimationScalar
  public let opacity: AnimationScalar
  var scalars: [AnimationScalar] { [travel, x, y, angle, squash, opacity] }
  func pose(in context: AnimationContext, settings: [String: AnimationValue]) -> Pose {
    let travel = travel.resolve(in: context, settings: settings)
    return Pose(
      point: CGPoint(
        x: context.initial.point.x + (context.destination.x - context.initial.point.x) * travel
          + x.resolve(in: context, settings: settings),
        y: context.initial.point.y + (context.destination.y - context.initial.point.y) * travel
          + y.resolve(in: context, settings: settings)),
      angle: context.initial.angle * (1 - travel) + angle.resolve(in: context, settings: settings),
      squash: squash.resolve(in: context, settings: settings),
      opacity: opacity.resolve(in: context, settings: settings))
  }
}

/// Versioned, installable data plugin.
///
/// Size and complexity limits are checked before registration.
public struct KeyframeAnimation: Codable, AnimationPlugin {
  public let version: Int
  public let descriptor: AnimationDescriptor
  public let keyframes: [AnimationKeyframe]
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 65_536 else { throw CocoaError(.fileReadTooLarge) }
    let plugin = try JSONDecoder().decode(Self.self, from: data)
    guard plugin.isValid else { throw CocoaError(.fileReadCorruptFile) }
    return plugin
  }
  public var isValid: Bool {
    guard version == 1, descriptor.isValid, (2...256).contains(keyframes.count),
      keyframes.first?.time == 0, keyframes.last?.time == 1,
      keyframes.allSatisfy({
        $0.time.isFinite && (0...1).contains($0.time)
          && $0.scalars.allSatisfy { $0.isValid(settings: descriptor.settings) }
      })
    else { return false }
    return zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.time < $1.time }
  }
  public func start(in context: AnimationContext) -> Pose {
    context.stage == .entry ? Pose(point: context.finalFrame.origin) : context.initial
  }
  public func frame(
    in context: AnimationContext, progress: Double, settings: [String: AnimationValue]
  ) -> Pose {
    // Registered data is validated, and progress is bounded by the host.
    let progress = min(max(progress, 0), 1)
    var index = 1
    while index < keyframes.count - 1 && keyframes[index].time < progress { index += 1 }
    let first = keyframes[index - 1]
    let last = keyframes[index]
    var t = (progress - first.time) / (last.time - first.time)
    switch last.curve {
    case .linear: break
    case .easeOut: t = ease(t)
    case .easeInOut: t = t * t * (3 - 2 * t)
    }
    return first.pose(in: context, settings: settings).interpolated(
      to: last.pose(in: context, settings: settings), progress: t)
  }
}
