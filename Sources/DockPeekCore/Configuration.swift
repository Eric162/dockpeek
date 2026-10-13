public struct AnimationIdentifier: RawRepresentable, Equatable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let slide = Self(rawValue: "slide")
  public static let tumble = Self(rawValue: "tumble")
  public static let none = Self(rawValue: "none")
  public init(from decoder: Decoder) throws {
    let values = try decoder.singleValueContainer()
    let id = try values.decode(String.self)
    guard validAnimationIdentifier(id) else {
      throw DecodingError.dataCorruptedError(in: values, debugDescription: "Invalid animation ID")
    }
    self.init(rawValue: id)
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.singleValueContainer()
    try values.encode(rawValue)
  }
}

public struct Configuration: Codable, Sendable {
  public var enabled = true
  public var allowedApps = ["com.openai.codex", "com.anysphere.sand"]
  public var peekFraction = 1.0 / 3
  public var entryAnimation = AnimationIdentifier.tumble
  public var dismissAnimation = AnimationIdentifier.slide
  public var slideDuration = 0.35
  public var dismissDuration = 0.25
  public var tumbleDuration = 1.4
  public var scrollDismisses = true
  public var rightClickDismisses = true
  public var openAppOnClick = true
  public var applicationPaths: [String: String] = [:]
  /// Values are retained separately for each plugin and transition direction.
  public var entrySettings: [String: [String: AnimationValue]] = [:]
  public var dismissalSettings: [String: [String: AnimationValue]] = [:]

  public func settings(for id: String, stage: AnimationStage) -> [String: AnimationValue] {
    var values = (stage == .entry ? entrySettings : dismissalSettings)[id] ?? [:]
    if values["duration"] == nil {
      if id == "slide" {
        values["duration"] = .number(stage == .entry ? slideDuration : dismissDuration)
      }
      if id == "tumble" { values["duration"] = .number(tumbleDuration) }
    }
    return values
  }

  public init() {}
  enum CodingKeys: String, CodingKey {
    case enabled, allowedApps, peekFraction, entryAnimation, dismissAnimation
    case slideDuration, dismissDuration, tumbleDuration, scrollDismisses, rightClickDismisses
    case openAppOnClick, applicationPaths, entrySettings, dismissalSettings
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
      try values.decodeIfPresent(T.self, forKey: key) ?? fallback
    }
    enabled = try value(.enabled, enabled)
    allowedApps = try value(.allowedApps, allowedApps)
    peekFraction = try value(.peekFraction, peekFraction)
    entryAnimation = try value(.entryAnimation, entryAnimation)
    dismissAnimation = try value(.dismissAnimation, dismissAnimation)
    slideDuration = try value(.slideDuration, slideDuration)
    dismissDuration = try value(.dismissDuration, dismissDuration)
    tumbleDuration = try value(.tumbleDuration, tumbleDuration)
    scrollDismisses = try value(.scrollDismisses, scrollDismisses)
    rightClickDismisses = try value(.rightClickDismisses, rightClickDismisses)
    applicationPaths = try value(.applicationPaths, applicationPaths)
    entrySettings = try value(.entrySettings, entrySettings)
    dismissalSettings = try value(.dismissalSettings, dismissalSettings)
    openAppOnClick = try value(.openAppOnClick, openAppOnClick)
  }
  public var isValid: Bool {
    peekFraction > 0 && peekFraction <= 1
      && [slideDuration, dismissDuration, tumbleDuration].allSatisfy {
        $0.isFinite && $0 > 0 && $0 <= AnimationRegistry.maximumDuration
      }
      && validAnimationIdentifier(entryAnimation.rawValue)
      && validAnimationIdentifier(dismissAnimation.rawValue)
      && entrySettings.count <= 66 && dismissalSettings.count <= 66
      && (Array(entrySettings.values) + Array(dismissalSettings.values)).allSatisfy {
        $0.count <= 16
      }
      && allowedApps.allSatisfy { !$0.isEmpty }
  }
}
