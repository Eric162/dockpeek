import CoreGraphics
import Foundation
import Testing

@testable import DockPeekCore

struct WorkerStateTests {
  private let now = Date(timeIntervalSince1970: 100)
  private var config: Configuration {
    var config = Configuration()
    config.allowedApps = ["test.app"]
    return config
  }
  private func observation(_ badge: String = "3", covered: Bool = false) -> BadgeObservation {
    BadgeObservation(bundle: "test.app", badge: badge, dockVisible: covered)
  }
  @Test
  func dismissalPersistsUntilBadgeChangesOrClears() {
    var state = WorkerState()
    #expect(
      state.update(configuration: config, observations: [observation()])["test.app"]?.badge == "3")
    state.dismiss("test.app")
    state.dismiss("missing")
    #expect(state.update(configuration: config, observations: [observation()]).isEmpty)
    #expect(
      state.update(configuration: config, observations: [observation("8")])["test.app"]?.badge
        == "8")
    state.dismiss("test.app")
    #expect(state.update(configuration: config, observations: [observation("")]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation("8")]).count == 1)
  }
  @Test
  func dockReturnSlidesButChangedBadgesUseConfiguredStyle() {
    var state = WorkerState()
    #expect(state.update(configuration: config, observations: [observation(covered: true)]).isEmpty)
    #expect(
      state.update(configuration: config, observations: [observation()])["test.app"]?.entry
        == .slide)
    _ = state.update(configuration: config, observations: [observation(covered: true)])
    #expect(
      state.update(configuration: config, observations: [observation("8")])["test.app"]?.entry
        == .tumble)
    state.dismiss("test.app")
    #expect(
      state.update(configuration: config, observations: [observation("8", covered: true)]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation("8")]).isEmpty)
  }
  @Test
  func appActivationTemporarilyHidesOnlyItsPeek() {
    var state = WorkerState()
    var settings = config
    settings.allowedApps.append("other.app")
    let other = BadgeObservation(bundle: "other.app", badge: "2")
    _ = state.update(configuration: settings, observations: [observation(), other])
    let active = BadgeObservation(bundle: "test.app", badge: "3", appActive: true)
    let result = state.update(configuration: settings, observations: [active, other])
    #expect(result["test.app"] == nil)
    #expect(result["other.app"]?.badge == "2")
    #expect(
      state.update(configuration: settings, observations: [observation(), other])["test.app"]?
        .entry == .slide)
  }
  @Test
  func badgesUpdateAndClearWhileAppIsActive() {
    var state = WorkerState()
    _ = state.update(configuration: config, observations: [observation()])
    #expect(
      state.update(
        configuration: config,
        observations: [
          BadgeObservation(bundle: "test.app", badge: "8", appActive: true)
        ]
      ).isEmpty)
    #expect(
      state.update(configuration: config, observations: [observation("8")])["test.app"]?.badge
        == "8")
    _ = state.update(
      configuration: config,
      observations: [
        BadgeObservation(bundle: "test.app", badge: "", appActive: true)
      ])
    #expect(state.update(configuration: config, observations: [observation("")]).isEmpty)
    #expect(
      state.update(configuration: config, observations: [observation()])["test.app"]?.entry
        == .tumble)
  }
  @Test
  func activationPreservesExplicitDismissalAndDockCoverage() {
    var state = WorkerState()
    _ = state.update(configuration: config, observations: [observation()])
    state.dismiss("test.app")
    let active = BadgeObservation(bundle: "test.app", badge: "3", appActive: true)
    #expect(state.update(configuration: config, observations: [active]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation()]).isEmpty)
    _ = state.update(
      configuration: config,
      observations: [
        BadgeObservation(bundle: "test.app", badge: "8", dockVisible: true, appActive: true)
      ])
    #expect(
      state.update(configuration: config, observations: [observation("8", covered: true)]).isEmpty)
    #expect(
      state.update(configuration: config, observations: [observation("8")])["test.app"]?.entry
        == .slide)
  }
  @Test
  func failuresAndDisabledSettingsHideUntilValidInputReturns() {
    var state = WorkerState()
    _ = state.update(configuration: config, observations: [observation()])
    #expect(state.update(configuration: nil, observations: [observation()]).isEmpty)
    #expect(state.update(configuration: config, observations: nil).isEmpty)
    var invalid = config
    invalid.peekFraction = 2
    #expect(state.update(configuration: invalid, observations: [observation()]).isEmpty)
    var disabled = config
    disabled.enabled = false
    #expect(state.update(configuration: disabled, observations: [observation()]).isEmpty)
    var disallowed = config
    disallowed.allowedApps = []
    #expect(state.update(configuration: disallowed, observations: [observation()]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation()]).count == 1)
  }
  @Test
  func temporaryTestOverridesDisabledSettingsAndExpiresAtBoundary() {
    var state = WorkerState()
    var disabled = config
    disabled.enabled = false
    let test = PeekTestRequest(bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now)
    let visible = state.update(
      configuration: disabled, observations: [observation("")], test: test, now: now)
    #expect(visible["test.app"]?.badge == "3")
    #expect(visible["test.app"]?.key == "test-\(test.token)")
    state.dismiss("test.app")
    #expect(
      state.update(configuration: disabled, observations: [observation()], test: test, now: now)
        .isEmpty)
    let next = PeekTestRequest(bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now)
    #expect(
      state.update(configuration: disabled, observations: [observation()], test: next, now: now)
        .count == 1)
    #expect(
      state.update(
        configuration: disabled, observations: [observation()], test: next,
        now: next.expiresAt
      ).isEmpty)
    #expect(
      state.update(
        configuration: config, observations: [observation()], test: next,
        now: next.expiresAt)["test.app"]?.key == "3")
    #expect(!test.isActive(at: test.expiresAt))
  }
  @Test
  func disappearedAppsReleaseDismissalState() {
    var state = WorkerState()
    _ = state.update(configuration: config, observations: [observation()])
    state.dismiss("test.app")
    #expect(state.update(configuration: config, observations: []).isEmpty)
    #expect(state.update(configuration: config, observations: [observation()]).count == 1)
  }
  @Test(arguments: EntryAnimation.allCases)
  func presentationEntryAndTargetMovement(_ animation: EntryAnimation) {
    var motion = PresentationMotion()
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let target = CGPoint(x: 900, y: -55)
    #expect(motion.step(now: 0, configuration: config) == nil)
    motion.hide(animation: .slide, now: 0)
    motion.show(at: target, screen: screen, animation: animation, now: 10)
    #expect(motion.isAnimating)
    _ = motion.step(now: 9, configuration: config)
    _ = motion.step(now: 10.1, configuration: config)
    #expect(motion.step(now: 12, configuration: config)?.point == target)
    #expect(motion.phase == .shown)
    #expect(!motion.isAnimating)
    motion.target.x = 1000
    #expect(motion.step(now: 13, configuration: config)?.point.x == 1000)
  }
  @Test(arguments: DismissAnimation.allCases)
  func interruptedEntryAndDismissalComplete(_ animation: DismissAnimation) {
    var motion = PresentationMotion()
    motion.show(
      at: CGPoint(x: 1900, y: -55), screen: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      animation: .tumble, now: 0)
    _ = motion.step(now: 0.2, configuration: config)
    let start = motion.current.point
    motion.hide(animation: animation, now: 0.2)
    motion.hide(animation: .slide, now: 0.3)
    let first = motion.step(now: 0.2, configuration: config)
    if animation == .slide { #expect(first?.point == start) } else { #expect(first == nil) }
    #expect(motion.step(now: 1, configuration: config) == nil)
    #expect(motion.phase == .hidden)
  }
  @Test
  func animationEnumsPreserveJSONAndRejectUnknownValues() throws {
    let decoded = try JSONDecoder().decode(
      Configuration.self,
      from: Data(#"{"entryAnimation":"slide","dismissAnimation":"none"}"#.utf8))
    #expect(decoded.entryAnimation == .slide)
    #expect(decoded.dismissAnimation == .none)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
    #expect(json["entryAnimation"] as? String == "slide")
    #expect(json["dismissAnimation"] as? String == "none")
    #expect(EntryAnimation.allCases.count == 3)
    #expect(DismissAnimation.allCases.count == 2)
  }
}
