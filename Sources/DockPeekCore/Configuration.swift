public struct AnimationIdentifier: RawRepresentable, Equatable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let slide = Self(rawValue: "slide")
  public static let tumble = Self(rawValue: "tumble")
  public static let none = Self(rawValue: "none")
  public static let allCases: [Self] = [.slide, .tumble, .none]
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
public typealias EntryAnimation = AnimationIdentifier
public typealias DismissAnimation = AnimationIdentifier

public struct Configuration: Codable, Sendable {
  public var enabled = true
  public var allowedApps = ["com.openai.codex", "com.anysphere.sand"]
  public var peekFraction = 1.0 / 3
  public var entryAnimation = EntryAnimation.tumble
  public var dismissAnimation = DismissAnimation.slide
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
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    allowedApps = try values.decodeIfPresent([String].self, forKey: .allowedApps) ?? allowedApps
    peekFraction = try values.decodeIfPresent(Double.self, forKey: .peekFraction) ?? peekFraction
    entryAnimation =
      try values.decodeIfPresent(EntryAnimation.self, forKey: .entryAnimation) ?? entryAnimation
    dismissAnimation =
      try values.decodeIfPresent(DismissAnimation.self, forKey: .dismissAnimation)
      ?? dismissAnimation
    slideDuration = try values.decodeIfPresent(Double.self, forKey: .slideDuration) ?? slideDuration
    dismissDuration =
      try values.decodeIfPresent(Double.self, forKey: .dismissDuration) ?? dismissDuration
    tumbleDuration =
      try values.decodeIfPresent(Double.self, forKey: .tumbleDuration) ?? tumbleDuration
    scrollDismisses =
      try values.decodeIfPresent(Bool.self, forKey: .scrollDismisses) ?? scrollDismisses
    rightClickDismisses =
      try values.decodeIfPresent(Bool.self, forKey: .rightClickDismisses) ?? rightClickDismisses
    applicationPaths =
      try values.decodeIfPresent([String: String].self, forKey: .applicationPaths)
      ?? applicationPaths
    entrySettings =
      try values.decodeIfPresent([String: [String: AnimationValue]].self, forKey: .entrySettings)
      ?? [:]
    dismissalSettings =
      try values.decodeIfPresent(
        [String: [String: AnimationValue]].self, forKey: .dismissalSettings) ?? [:]
    openAppOnClick =
      try values.decodeIfPresent(Bool.self, forKey: .openAppOnClick) ?? openAppOnClick
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
