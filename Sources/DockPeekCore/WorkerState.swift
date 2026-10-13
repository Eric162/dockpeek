import Foundation

public struct BadgeObservation: Sendable {
  public let bundle: String
  public let badge: String
  public let dockVisible: Bool
  /// True only for the frontmost app, rather than every running app.
  public let appActive: Bool

  public init(
    bundle: String, badge: String, dockVisible: Bool = false, appActive: Bool = false
  ) {
    self.bundle = bundle
    self.badge = badge
    self.dockVisible = dockVisible
    self.appActive = appActive
  }
}

public struct VisibleBadge: Equatable, Sendable {
  public let badge: String
  public let key: String
  public let entry: AnimationIdentifier
}

/// Decides what may be shown.
///
/// AppKit only renders the returned desired state.
public struct WorkerState: Sendable {
  private var dismissed: [String: String] = [:]
  private var covered: [String: String] = [:]
  public private(set) var visible: [String: VisibleBadge] = [:]

  public init() {}

  public mutating func dismiss(_ bundle: String) {
    if let badge = visible.removeValue(forKey: bundle) { dismissed[bundle] = badge.key }
  }

  public mutating func update(
    configuration: Configuration?, observations: [BadgeObservation]?,
    test: PeekTestRequest? = nil, now: Date = Date()
  ) -> [String: VisibleBadge] {
    visible.removeAll(keepingCapacity: true)
    guard let configuration, configuration.isValid, let observations else { return visible }
    let test = test.flatMap { $0.isActive(at: now) ? $0 : nil }
    var allowed = configuration.enabled ? Set(configuration.allowedApps) : []
    if let test { allowed.insert(test.bundleIdentifier) }
    let bundles = Set(observations.map(\.bundle)).intersection(allowed)
    dismissed = dismissed.filter { bundles.contains($0.key) }
    covered = covered.filter { bundles.contains($0.key) }
    for observation in observations where allowed.contains(observation.bundle) {
      evaluate(observation, configuration: configuration, test: test)
    }
    return visible
  }

  private mutating func evaluate(
    _ observation: BadgeObservation, configuration: Configuration, test: PeekTestRequest?
  ) {
    let badge: String
    let key: String
    if let test, test.bundleIdentifier == observation.bundle {
      badge = "3"
      key = "test-\(test.token)"
    } else {
      badge = observation.badge
      key = badge
    }
    if badge.isEmpty {
      dismissed.removeValue(forKey: observation.bundle)
      covered.removeValue(forKey: observation.bundle)
      return
    }
    if dismissed[observation.bundle] != key { dismissed.removeValue(forKey: observation.bundle) }
    guard dismissed[observation.bundle] != key else { return }
    if observation.dockVisible || observation.appActive {
      covered[observation.bundle] = badge
      return
    }
    let entry: AnimationIdentifier =
      covered.removeValue(forKey: observation.bundle) == badge
      ? .slide : configuration.entryAnimation
    visible[observation.bundle] = VisibleBadge(badge: badge, key: key, entry: entry)
  }
}
