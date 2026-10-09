import Foundation

public struct Configuration: Codable {
  public var enabled = true
  public var allowedApps = ["com.openai.codex", "com.anysphere.sand"]
  public var peekFraction = 1.0 / 3
  public var entryAnimation = "tumble"
  public var dismissAnimation = "slide"
  public var slideDuration = 0.35
  public var dismissDuration = 0.25
  public var tumbleDuration = 1.4
  public var scrollDismisses = true
  public var rightClickDismisses = true
  public var openAppOnClick = true
  public var applicationPaths: [String: String] = [:]

  public init() {}
  enum CodingKeys: String, CodingKey {
    case enabled, allowedApps, peekFraction, entryAnimation, dismissAnimation
    case slideDuration, dismissDuration, tumbleDuration, scrollDismisses, rightClickDismisses
    case openAppOnClick, applicationPaths
  }
  public init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    allowedApps = try values.decodeIfPresent([String].self, forKey: .allowedApps) ?? allowedApps
    peekFraction = try values.decodeIfPresent(Double.self, forKey: .peekFraction) ?? peekFraction
    entryAnimation =
      try values.decodeIfPresent(String.self, forKey: .entryAnimation) ?? entryAnimation
    dismissAnimation =
      try values.decodeIfPresent(String.self, forKey: .dismissAnimation) ?? dismissAnimation
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
    openAppOnClick =
      try values.decodeIfPresent(Bool.self, forKey: .openAppOnClick) ?? openAppOnClick
  }
  public var isValid: Bool {
    peekFraction > 0 && peekFraction <= 1
      && ["slide", "tumble", "none"].contains(entryAnimation)
      && ["slide", "none"].contains(dismissAnimation)
      && [slideDuration, dismissDuration, tumbleDuration].allSatisfy { $0.isFinite && $0 > 0 }
      && allowedApps.allSatisfy { !$0.isEmpty }
  }
}
