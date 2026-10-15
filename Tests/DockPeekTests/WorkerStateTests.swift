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
  private func observation(_ badge: String = "3", covered: Bool = false, active: Bool = false)
    -> BadgeObservation
  {
    BadgeObservation(bundle: "test.app", badge: badge, dockVisible: covered, appActive: active)
  }
  @Test
  func dismissalPersistsUntilBadgeChangesClearsOrAppDisappears() {
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
    state.dismiss("test.app")
    #expect(state.update(configuration: config, observations: []).isEmpty)
    #expect(state.update(configuration: config, observations: [observation("8")]).count == 1)
  }
  @Test(arguments: [false, true])
  func temporaryCoverageHidesOnlyItsPeekAndObservesBadgeChanges(active: Bool) {
    var state = WorkerState()
    var settings = config
    settings.allowedApps.append("other.app")
    let other = BadgeObservation(bundle: "other.app", badge: "2")
    func observations(_ badge: String = "3", hidden: Bool = false) -> [BadgeObservation] {
      [observation(badge, covered: hidden && !active, active: hidden && active), other]
    }
    _ = state.update(configuration: settings, observations: observations())
    let result = state.update(configuration: settings, observations: observations(hidden: true))
    #expect(result["test.app"] == nil)
    #expect(result["other.app"]?.badge == "2")
    #expect(
      state.update(configuration: settings, observations: observations())["test.app"]?.entry
        == .slide)
    _ = state.update(configuration: settings, observations: observations(hidden: true))
    #expect(
      state.update(configuration: settings, observations: observations("8"))["test.app"]?.entry
        == .tumble)
    #expect(
      state.update(configuration: settings, observations: observations("9", hidden: true))[
        "test.app"] == nil)
    #expect(
      state.update(configuration: settings, observations: observations("9"))["test.app"]?.badge
        == "9")
    _ = state.update(configuration: settings, observations: observations("", hidden: true))
    #expect(
      state.update(configuration: settings, observations: observations(""))["test.app"] == nil)
    #expect(
      state.update(configuration: settings, observations: observations())["test.app"]?.entry
        == .tumble)
  }
  @Test
  func activationPreservesExplicitDismissalAndDockCoverage() {
    var state = WorkerState()
    _ = state.update(configuration: config, observations: [observation()])
    state.dismiss("test.app")
    #expect(state.update(configuration: config, observations: [observation(active: true)]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation(covered: true)]).isEmpty)
    #expect(state.update(configuration: config, observations: [observation()]).isEmpty)
    _ = state.update(
      configuration: config, observations: [observation("8", covered: true, active: true)])
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
  func previewRemainsVisibleWhileSettingsIsActive() {
    var state = WorkerState()
    let request = PeekTestRequest(
      bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now)
    let result = state.update(
      configuration: config, observations: [observation(active: true)], test: request, now: now)
    #expect(result["test.app"]?.badge == "3")
    #expect(
      state.update(
        configuration: config, observations: [observation(active: true)], test: request,
        now: request.expiresAt
      ).isEmpty)
  }
  @Test
  func temporaryTestOverridesDisabledSettingsAndExpiresAtBoundary() throws {
    var state = WorkerState()
    var disabled = config
    disabled.enabled = false
    let request = PeekTestRequest(
      bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now)
    let test = try JSONDecoder().decode(PeekTestRequest.self, from: JSONEncoder().encode(request))
    #expect(test.bundleIdentifier == "test.app")
    #expect(test.applicationPath == "/Test.app")
    #expect(test.token == request.token)
    #expect(test.expiresAt == now.addingTimeInterval(10))
    #expect(test.isActive(at: now))
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
        configuration: disabled, observations: [observation()], test: next, now: next.expiresAt
      ).isEmpty)
    #expect(
      state.update(
        configuration: config, observations: [observation()], test: next, now: next.expiresAt)[
          "test.app"]?.key == "3")
  }
}
