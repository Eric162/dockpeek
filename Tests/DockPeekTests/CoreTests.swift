import CoreGraphics
import Foundation
import Testing

@testable import DockPeekCore

struct CoreTests {
  @Test(arguments: [0.0, -0.1, 1.1, Double.infinity, Double.nan])
  func testInvalidPeekFractions(_ fraction: Double) {
    var config = Configuration()
    config.peekFraction = fraction
    #expect(!config.isValid)
  }

  @Test(arguments: [0.0, -1.0, Double.infinity, Double.nan])
  func testInvalidDurations(_ duration: Double) {
    for keyPath in [
      \Configuration.slideDuration, \Configuration.dismissDuration,
      \Configuration.tumbleDuration,
    ] {
      var config = Configuration()
      config[keyPath: keyPath] = duration
      #expect(!config.isValid)
    }
  }

  @Test
  func testInvalidAppIdentifiersAndDismissAnimation() throws {
    var config = Configuration()
    config.allowedApps = [""]
    #expect(!config.isValid)
    config.allowedApps = []
    #expect(config.isValid)
    config.dismissAnimation = "tumble"
    #expect(!config.isValid)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Configuration.self, from: Data(#"{"enabled":1}"#.utf8))
    }
  }

  @Test
  func testRegexRejectsInvalidPatternsAndMissingCaptures() {
    #expect(match("[", "text") == nil)
    #expect(match("(a)?b", "b") == nil)
    #expect(match("(🚢)", "🚢") == ["🚢"])
  }

  @Test
  func testConfigurationDefaultsAndValidation() throws {
    var config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
    #expect(config.isValid)
    #expect(config.openAppOnClick && config.scrollDismisses && config.rightClickDismisses)
    config.peekFraction = 0
    #expect(!(config.isValid))
    config.peekFraction = 0.4
    config.tumbleDuration = .infinity
    #expect(!(config.isValid))
    config.tumbleDuration = 1.4
    config.entryAnimation = "invalid"
    #expect(!(config.isValid))
  }

  @Test
  func testPeekFractionAtDifferentScreenEdges() {
    for edge in [0.0, -1080.0, 1692.0] {
      for fraction in [0.1, 1.0 / 3, 1.0] {
        let visible = restingY(edge: edge, fraction: fraction) + iconTop - edge
        #expect(abs(visible / iconSize - fraction) <= 0.0001)
      }
    }
  }

  @Test
  func testTumbleTravelsAcrossThreeShrinkingHopsWhileSpinning() {
    for fromLeft in [true, false] {
      let start = CGPoint(x: fromLeft ? -128 : 3008, y: -37)
      let target = CGPoint(x: 1759, y: restingY(edge: 0, fraction: 1.0 / 3))
      #expect(
        tumblePose(progress: 0, start: start, target: target, fromLeft: fromLeft).point == start)
      let final = tumblePose(progress: 1, start: start, target: target, fromLeft: fromLeft)
      #expect(final.point == target)
      #expect(abs(abs(final.angle) - 4 * .pi) <= 0.0001)
      #expect(final.squash == 1)
      var previous = start.x
      for t in stride(from: 0.0, through: 1.0, by: 0.01) {
        let pose = tumblePose(progress: t, start: start, target: target, fromLeft: fromLeft)
        #expect(fromLeft ? pose.point.x >= previous : pose.point.x <= previous)
        previous = pose.point.x
      }
      for contact in [0.42, 0.70, 0.88] {
        let pose = tumblePose(progress: contact, start: start, target: target, fromLeft: fromLeft)
        #expect(abs(pose.point.y - start.y) <= 0.0001)
        #expect(pose.point.x != target.x)
        #expect(abs(pose.angle) < 4 * .pi)
      }
      let peaks = [0.21, 0.56, 0.79].map {
        tumblePose(progress: $0, start: start, target: target, fromLeft: fromLeft).point.y - start.y
      }
      #expect(peaks[0] > peaks[1])
      #expect(peaks[1] > peaks[2])
      #expect(peaks[2] > 0)
    }
  }

  @Test
  func testDockReturnSlidesAndNewBadgesUseConfiguredAnimation() {
    #expect(entryStyle(badge: "3", coveredBadge: "3", configured: "tumble") == "slide")
    #expect(entryStyle(badge: "8", coveredBadge: "3", configured: "tumble") == "tumble")
  }

  @Test
  func testTemporaryRequestExpiresAndRoundTrips() throws {
    let now = Date()
    let request = PeekTestRequest(
      bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now)
    #expect(request.isActive)
    #expect(request.expiresAt.timeIntervalSince(now) == 10)
    #expect(
      !(PeekTestRequest(
        bundleIdentifier: "test.app", applicationPath: "/Test.app", now: now.addingTimeInterval(-11)
      ).isActive))
    let decoded = try JSONDecoder().decode(
      PeekTestRequest.self, from: JSONEncoder().encode(request))
    #expect(decoded.token == request.token)
    #expect(decoded.bundleIdentifier == request.bundleIdentifier)
  }

  @Test
  func testDockSnapshotBadgesClearAndMalformedGeometryIsIgnored() {
    let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    func snapshot(badge: String?, x: String = "120") -> String {
      """
          ELEMENT
          AXTitle=TextEdit
          AXURL=\(url.absoluteString)
          AXFrame=value = x:\(x) y:1692 w:67 h:83
      """ + (badge.map { "\n    AXStatusLabel=\($0)" } ?? "")
    }
    let first = tiles(snapshot(badge: "3"))
    #expect(first.count == 1)
    #expect(first.first?.badge == "3")
    #expect(first.first?.rect.minX == 120)
    #expect(tiles(snapshot(badge: "8")).first?.badge == "8")
    #expect(tiles(snapshot(badge: nil)).first?.badge == nil)
    #expect(tiles(snapshot(badge: "3", x: "-")).isEmpty)
    #expect(tiles("unrelated AX output").isEmpty)
  }
}
