import CoreGraphics
import Foundation

public enum AnimationStage: String, Codable, CaseIterable, Sendable { case entry, dismissal }

/// Only the host creates windows and advances time.
///
/// Native implementations are trusted code.
public protocol AnimationPlugin: Sendable {
  var descriptor: AnimationDescriptor { get }
  var isValid: Bool { get }
  func start(in context: AnimationContext) -> Pose
  func frame(in context: AnimationContext, progress: Double, settings: [String: AnimationValue])
    -> Pose
}

extension AnimationPlugin {
  public var isValid: Bool { descriptor.isValid }
}

public struct AnimationContext: Sendable {
  public let stage: AnimationStage
  public let finalFrame: CGRect
  public let screen: CGRect
  public let initial: Pose
  public let badge: String
  public var unreadCount: Int? { Int(badge).flatMap { $0 >= 0 ? $0 : nil } }
  public var hasUnread: Bool { !badge.isEmpty && badge != "0" }
  public var fromLeft: Bool {
    finalFrame.midX - screen.minX <= screen.maxX - finalFrame.midX
  }
  public var destination: CGPoint {
    stage == .entry
      ? finalFrame.origin
      : CGPoint(x: initial.point.x, y: screen.minY - finalFrame.height - 4)
  }
  public init(
    stage: AnimationStage, finalFrame: CGRect, screen: CGRect, initial: Pose, badge: String
  ) {
    self.stage = stage
    self.finalFrame = finalFrame
    self.screen = screen
    self.initial = initial
    self.badge = badge
  }
}

public enum AnimationValue: Hashable, Codable, Sendable {
  case number(Double)
  case toggle(Bool)
  case choice(String)
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let boolean = try? value.decode(Bool.self) {
      self = .toggle(boolean)
    } else if let number = try? value.decode(Double.self) {
      self = .number(number)
    } else {
      self = .choice(try value.decode(String.self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .number(let number): try value.encode(number)
    case .toggle(let boolean): try value.encode(boolean)
    case .choice(let string): try value.encode(string)
    }
  }
  public var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
}

public struct AnimationSetting: Codable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable { case number, toggle, choice }
  public let id: String
  public let name: String
  public let kind: Kind
  public let defaultValue: AnimationValue
  public let minimum: Double?
  public let maximum: Double?
  public let choices: [String]?

  public func accepts(_ value: AnimationValue) -> Bool {
    switch (kind, value) {
    case (.number, .number(let number)):
      guard let minimum, let maximum else { return false }
      return number.isFinite && (minimum...maximum).contains(number)
    case (.toggle, .toggle): return true
    case (.choice, .choice(let choice)): return choices?.contains(choice) == true
    default: return false
    }
  }
  public var isValid: Bool {
    guard !id.isEmpty, id.count <= 64, !name.isEmpty, name.count <= 100 else { return false }
    switch kind {
    case .number:
      guard let minimum, let maximum, minimum.isFinite, maximum.isFinite,
        minimum <= maximum, abs(minimum) <= 10_000, abs(maximum) <= 10_000
      else { return false }
    case .toggle: break
    case .choice:
      guard let choices, !choices.isEmpty, choices.count <= 16,
        Set(choices).count == choices.count,
        choices.allSatisfy({ !$0.isEmpty && $0.count <= 64 })
      else { return false }
    }
    return accepts(defaultValue)
  }
}

public struct AnimationDescriptor: Codable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let stages: [AnimationStage]
  public let settings: [AnimationSetting]
  public var isValid: Bool {
    guard validAnimationIdentifier(id), id != "none", !name.isEmpty, name.count <= 100,
      !stages.isEmpty, Set(stages).count == stages.count, settings.count <= 16,
      Set(settings.map(\.id)).count == settings.count, settings.allSatisfy(\.isValid),
      let duration = settings.first(where: { $0.id == "duration" }), duration.kind == .number,
      let minimum = duration.minimum, let maximum = duration.maximum
    else { return false }
    return minimum > 0 && maximum <= AnimationRegistry.maximumDuration
  }
  public func resolved(_ supplied: [String: AnimationValue]) -> [String: AnimationValue] {
    Dictionary(
      uniqueKeysWithValues: settings.map {
        let value = supplied[$0.id] ?? $0.defaultValue
        return ($0.id, $0.accepts(value) ? value : $0.defaultValue)
      })
  }
}

public func validAnimationIdentifier(_ id: String) -> Bool {
  !id.isEmpty && id.count <= 64
    && id.utf8.allSatisfy {
      (97...122).contains($0) || (48...57).contains($0) || [45, 46].contains($0)
    }
}

public struct AnimationRegistry: Sendable {
  public static let maximumDuration = 15.0
  public private(set) var plugins: [any AnimationPlugin] = [SlideAnimation(), TumbleAnimation()]
  public init() {}
  public mutating func register(_ plugin: any AnimationPlugin) throws {
    guard plugin.isValid, plugins.count < 66,
      !plugins.contains(where: { $0.descriptor.id == plugin.descriptor.id })
    else { throw CocoaError(.fileReadCorruptFile) }
    plugins.append(plugin)
  }
  public func plugin(id: String, stage: AnimationStage) -> (any AnimationPlugin)? {
    plugins.first { $0.descriptor.id == id && $0.descriptor.stages.contains(stage) }
  }
  public func accepts(_ config: Configuration) -> Bool {
    (config.entryAnimation == .none
      || plugin(id: config.entryAnimation.rawValue, stage: .entry) != nil)
      && (config.dismissAnimation == .none
        || plugin(id: config.dismissAnimation.rawValue, stage: .dismissal) != nil)
  }
}
