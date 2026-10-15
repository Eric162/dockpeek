import CoreGraphics
import Foundation
import Testing

@testable import DockPeekCore

struct CoreTests {
  @Test
  func dockFoldersAreExcludedEvenWhenTheyContainBundleMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let contents = root.appendingPathComponent("Downloads.bundle/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let info = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": "test.folder"], format: .xml, options: 0)
    try info.write(to: contents.appendingPathComponent("Info.plist"))
    let url = contents.deletingLastPathComponent()
    #expect(Bundle(url: url)?.bundleIdentifier == "test.folder")
    #expect(
      tiles(
        "    ELEMENT\nAXTitle=Downloads\nAXURL=\(url.absoluteString)\nAXFrame=value = x:1 y:2 w:67 h:83\n"
      )
      .isEmpty)
  }
  @Test(arguments: [0.0, -0.1, 1.1, Double.infinity, Double.nan])
  func testInvalidPeekFractions(_ fraction: Double) {
    var config = Configuration()
    config.peekFraction = fraction
    #expect(!config.isValid)
  }

  @Test(arguments: [0.0, -1.0, 15.01, Double.infinity, Double.nan])
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
    for json in [
      #"{"dismissAnimation":"TUMBLE"}"#, #"{"entryAnimation":"INVALID"}"#, #"{"enabled":1}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
      }
    }
  }

  @Test
  func testConfigurationDefaults() throws {
    let config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
    #expect(config.isValid)
    #expect(config.openAppOnClick && config.scrollDismisses && config.rightClickDismisses)
  }

  @Test
  func testPeekFractionAtDifferentScreenEdges() {
    for edge in [0.0, -1080.0, 1692.0] {
      for (fraction, expected) in [(0.1, 23.0), (1.0 / 3, 23), (1.0, 54)] {
        let visible = restingY(edge: edge, fraction: fraction) + 91 - edge
        #expect(abs(visible - expected) <= 0.0001)
        #expect(visible >= 23)
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
  func testDockSnapshotBadgesClearAndMalformedGeometryIsIgnored() {
    let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    func snapshot(badge: String?, x: String = "120") -> String {
      """
          ELEMENT
          AXTitle=TextEdit 🚢
          AXURL=\(url.absoluteString)
          AXFrame=value = x:\(x) y:1692 w:67 h:83
      """ + (badge.map { "\n    AXStatusLabel=\($0)" } ?? "")
    }
    let first = tiles(snapshot(badge: "3"))
    #expect(first.count == 1)
    #expect(first.first?.badge == "3")
    #expect(first.first?.name == "TextEdit 🚢")
    #expect(first.first?.rect.minX == 120)
    #expect(tiles(snapshot(badge: "8")).first?.badge == "8")
    #expect(tiles(snapshot(badge: nil)).first?.badge == nil)
    #expect(tiles(snapshot(badge: "3", x: "-")).isEmpty)
    #expect(
      tiles(snapshot(badge: "3").replacingOccurrences(of: "AXTitle=TextEdit 🚢", with: "")).isEmpty)
    #expect(tiles("unrelated AX output").isEmpty)
  }
}
