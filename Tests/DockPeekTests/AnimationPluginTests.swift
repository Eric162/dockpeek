import CoreGraphics
import Foundation
import Testing

@testable import DockPeekCore
@testable import DockPeekRuntime

struct AnimationPluginTests {
  let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
  let target = CGPoint(x: -900, y: -1130)
  func scalar(
    _ value: Double = 0, binding: String? = nil, multiplier: Double = 1,
    choices: [String: Double]? = nil
  ) -> AnimationScalar {
    AnimationScalar(value: value, binding: binding, multiplier: multiplier, choices: choices)
  }
  func setting(
    _ id: String, kind: AnimationSetting.Kind, value: AnimationValue, name: String? = nil,
    minimum: Double? = nil, maximum: Double? = nil, choices: [String]? = nil
  ) -> AnimationSetting {
    AnimationSetting(
      id: id, name: name ?? id, kind: kind, defaultValue: value,
      minimum: minimum, maximum: maximum, choices: choices)
  }
  func number(_ id: String, value: Double = 1, minimum: Double = 0.1, maximum: Double = 10)
    -> AnimationSetting
  {
    setting(id, kind: .number, value: .number(value), minimum: minimum, maximum: maximum)
  }
  var toggle: AnimationSetting { setting("bounce", kind: .toggle, value: .toggle(true)) }
  var choice: AnimationSetting {
    setting("direction", kind: .choice, value: .choice("up"), choices: ["up", "down"])
  }
  func descriptor(
    id: String = "test.fade", settings: [AnimationSetting]? = nil,
    stages: [AnimationStage] = [.entry, .dismissal]
  ) -> AnimationDescriptor {
    AnimationDescriptor(
      id: id, name: "Fade", stages: stages,
      settings: settings ?? [number("duration"), toggle, choice])
  }
  func frame(
    _ time: Double, curve: AnimationKeyframe.Curve = .linear, y: AnimationScalar? = nil,
    opacity: Double = 1
  ) -> AnimationKeyframe {
    AnimationKeyframe(
      time: time, curve: curve, travel: scalar(time), x: scalar(),
      y: y ?? scalar(), angle: scalar(), squash: scalar(1), opacity: scalar(opacity))
  }
  func plugin(id: String = "test.fade", version: Int = 1, frames: [AnimationKeyframe]? = nil)
    -> KeyframeAnimation
  {
    KeyframeAnimation(
      version: version, descriptor: descriptor(id: id),
      keyframes: frames ?? [frame(0, opacity: 0), frame(1)])
  }
  func context(stage: AnimationStage = .entry, badge: String = "4") -> AnimationContext {
    AnimationContext(
      stage: stage, finalFrame: CGRect(origin: target, size: CGSize(width: 128, height: 128)),
      screen: screen, initial: Pose(point: CGPoint(x: target.x, y: -1212)), badge: badge)
  }

  @Test
  func settingsRoundTripAndRejectIncorrectKinds() throws {
    for value in [AnimationValue.number(0.5), .toggle(false), .choice("down")] {
      #expect(
        try JSONDecoder().decode(AnimationValue.self, from: JSONEncoder().encode(value)) == value)
    }
    #expect(AnimationValue.toggle(false).number == nil)
    #expect(number("duration").accepts(.number(1)))
    #expect(!number("duration").accepts(.number(.nan)))
    #expect(!number("duration").accepts(.number(0)))
    #expect(!number("duration").accepts(.toggle(true)))
    #expect(toggle.accepts(.toggle(false)))
    #expect(choice.accepts(.choice("down")))
    #expect(!choice.accepts(.choice("other")))
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AnimationValue.self, from: Data("{}".utf8))
    }
    let resolved = descriptor().resolved(["duration": .number(99), "direction": .choice("down")])
    #expect(resolved["duration"] == .number(1))
    #expect(resolved["bounce"] == .toggle(true))
    #expect(resolved["direction"] == .choice("down"))
  }

  @Test
  func manifestBoundsAndDuplicateIds() throws {
    for id in ["", "../escape", "UPPER", String(repeating: "a", count: 65)] {
      #expect(!validAnimationIdentifier(id))
      #expect(!descriptor(id: id).isValid)
    }
    #expect(validAnimationIdentifier("test.fade-2"))
    for invalid in [
      descriptor(id: "none"), descriptor(stages: []), descriptor(stages: [.entry, .entry]),
      descriptor(settings: []), descriptor(settings: [toggle]),
      descriptor(settings: [number("duration", minimum: 0)]),
      descriptor(settings: [number("duration", maximum: 16)]),
      descriptor(settings: [number("duration"), number("duration")]),
    ] {
      #expect(!invalid.isValid)
    }
    let badSettings = [
      number("", minimum: 0), number("duration", minimum: 2, maximum: 1),
      number("duration", minimum: .nan), number("duration", maximum: 10_001),
      setting("bad", kind: .number, value: .number(1), name: ""),
      setting("bad", kind: .number, value: .number(1)),
      setting("bad", kind: .choice, value: .choice("a"), choices: []),
      setting("bad", kind: .choice, value: .choice("a"), choices: ["a", "a"]),
    ]
    for setting in badSettings { #expect(!setting.isValid) }
    var registry = AnimationRegistry()
    try registry.register(plugin())
    #expect(registry.plugin(id: "test.fade", stage: .entry) != nil)
    #expect(throws: CocoaError.self) { try registry.register(plugin()) }
    #expect(throws: CocoaError.self) { try registry.register(plugin(id: "slide")) }
    #expect(registry.plugin(id: "tumble", stage: .dismissal) == nil)
    var config = Configuration()
    #expect(registry.accepts(config))
    config.entryAnimation = .none
    config.dismissAnimation = .none
    #expect(registry.accepts(config))
    config.entryAnimation = AnimationIdentifier(rawValue: "missing")
    #expect(!registry.accepts(config))
    config.entryAnimation = .slide
    config.dismissAnimation = .tumble
    #expect(!registry.accepts(config))
    for index in 0..<63 { try registry.register(plugin(id: "test.\(index)")) }
    #expect(throws: CocoaError.self) { try registry.register(plugin(id: "test.overflow")) }
  }

  @Test
  func bindingsReceiveGeometryBadgeAndTypedSettings() {
    let context = context()
    let settings: [String: AnimationValue] = [
      "duration": .number(2), "bounce": .toggle(true), "direction": .choice("down"),
    ]
    for (binding, expected) in [
      ("width", 128.0), ("height", 128), ("screenTopOffset", 1130),
      ("unreadCount", 4), ("hasUnread", 1), ("direction", 1),
      ("setting.duration", 2), ("setting.bounce", 1),
    ] {
      let expression = scalar(1, binding: binding, multiplier: 2)
      #expect(expression.isValid(settings: descriptor().settings))
      #expect(expression.resolve(in: context, settings: settings) == 1 + expected * 2)
    }
    let mapped = scalar(binding: "setting.direction", choices: ["up": 10, "down": -10])
    #expect(mapped.isValid(settings: descriptor().settings))
    #expect(mapped.resolve(in: context, settings: settings) == -10)
    #expect(mapped.resolve(in: context, settings: ["direction": .choice("unknown")]) == 0)
    #expect(scalar(5).resolve(in: context, settings: [:]) == 5)
    #expect(scalar(binding: "setting.missing").resolve(in: context, settings: [:]) == 0)
    for invalid in [
      scalar(.nan), scalar(10_001), scalar(binding: "missing"),
      scalar(binding: "width", choices: ["bad": 1]),
      scalar(binding: "setting.direction"), scalar(choices: ["bad": 1]),
      scalar(multiplier: .infinity), scalar(choices: ["bad": .nan]),
    ] {
      #expect(!invalid.isValid(settings: descriptor().settings))
    }
    #expect(self.context(badge: "4+").unreadCount == nil)
    #expect(self.context(badge: "-2").unreadCount == nil)
    #expect(!self.context(badge: "").hasUnread)
    #expect(!self.context(badge: "0").hasUnread)
    #expect(scalar(binding: "hasUnread").resolve(in: self.context(badge: ""), settings: [:]) == 0)
    #expect(
      scalar(binding: "unreadCount").resolve(in: self.context(badge: "4+"), settings: [:]) == 0)
    #expect(
      scalar(binding: "direction").resolve(
        in: AnimationContext(
          stage: .entry,
          finalFrame: CGRect(x: -1900, y: -1130, width: 128, height: 128), screen: screen,
          initial: Pose(point: .zero), badge: ""), settings: [:]) == -1)
  }

  @Test
  func keyframeValidationAndInterpolation() throws {
    let plugin = plugin()
    #expect(plugin.isValid)
    let decoded = try KeyframeAnimation.decode(JSONEncoder().encode(plugin))
    #expect(decoded.descriptor.id == "test.fade")
    #expect(decoded.start(in: context()).point == target)
    #expect(decoded.start(in: context(stage: .dismissal)).point == context().initial.point)
    #expect(throws: CocoaError.self) {
      try KeyframeAnimation.decode(Data(repeating: 32, count: 65_537))
    }
    #expect(throws: CocoaError.self) {
      try KeyframeAnimation.decode(JSONEncoder().encode(self.plugin(version: 2)))
    }
    for frames in [
      [], [frame(0)], [frame(0.1), frame(1)], [frame(0), frame(0.9)],
      [frame(0), frame(0.5), frame(0.5), frame(1)], [frame(0), frame(.nan), frame(1)],
      [frame(0), frame(1, y: scalar(binding: "invalid"))],
    ] {
      #expect(!self.plugin(frames: frames).isValid)
    }
    for (curve, midpoint, quarter) in [
      (AnimationKeyframe.Curve.linear, 0.5, 0.25), (.easeOut, 0.875, 0.578125),
      (.easeInOut, 0.5, 0.15625),
    ] {
      let animation = self.plugin(frames: [frame(0, opacity: 0), frame(1, curve: curve)])
      let first = animation.frame(in: context(), progress: 0, settings: [:])
      let middle = animation.frame(in: context(), progress: 0.5, settings: [:])
      let last = animation.frame(in: context(), progress: 1, settings: [:])
      #expect(first.point == context().initial.point)
      #expect(last.point == target)
      #expect(last.opacity == 1)
      #expect(middle.opacity == midpoint)
      #expect(animation.frame(in: context(), progress: 0.25, settings: [:]).opacity == quarter)
    }
  }

  @Test
  func installedExampleBindsBothStagesAndScalarDefaults() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let example = try KeyframeAnimation.decode(
      Data(contentsOf: root.appendingPathComponent("docs/examples/fade.json")))
    for stage in AnimationStage.allCases {
      let context = context(stage: stage)
      let settings = example.descriptor.resolved([:])
      let first = example.frame(in: context, progress: 0, settings: settings)
      let last = example.frame(in: context, progress: 1, settings: settings)
      #expect(first.opacity == (stage == .entry ? 0 : 1))
      #expect(last.opacity == (stage == .entry ? 1 : 0))
    }
    for (expression, expected) in [
      (scalar(), 0.0), (scalar(binding: "setting.duration"), 2),
      (scalar(binding: "setting.direction", choices: ["up": 0, "down": 10]), 10),
    ] {
      let decoded = try JSONDecoder().decode(
        AnimationScalar.self, from: JSONEncoder().encode(expression))
      #expect(
        decoded.resolve(
          in: context(), settings: ["duration": .number(2), "direction": .choice("down")])
          == expected)
    }
  }

  @Test
  func deadlineSettlesStopsAndCapturesSettings() throws {
    var registry = AnimationRegistry()
    try registry.register(plugin())
    var config = Configuration()
    config.entrySettings["test.fade"] = ["duration": .number(15)]
    // This manifest has a tighter limit, so invalid supplied values use its default.
    var motion = PresentationMotion()
    motion.show(
      at: target, screen: screen, animation: AnimationIdentifier(rawValue: "test.fade"), now: 0,
      configuration: config, registry: registry, badge: "4")
    #expect(motion.step(now: 0.5)?.opacity == 0.5)
    config.entrySettings["test.fade"] = ["duration": .number(0.1)]
    #expect(motion.step(now: 0.75)?.opacity == 0.75)
    #expect(motion.step(now: 30)?.point == target)
    #expect(motion.current.opacity == 1 && motion.current.angle == 0 && motion.current.squash == 1)
    #expect(!motion.isAnimating)
    motion.hide(
      animation: AnimationIdentifier(rawValue: "test.fade"), now: 30,
      configuration: config, registry: registry, badge: "4")
    #expect(motion.step(now: 30.5) != nil)
    #expect(motion.step(now: 31) == nil)
    #expect(!motion.isAnimating)
    motion.show(
      at: target, screen: screen, animation: .slide, now: 40,
      configuration: config, registry: registry)
    let first = motion.step(now: 40.1)
    motion.hide(animation: .slide, now: 40.1, configuration: config)
    #expect(motion.step(now: 40.1)?.point == first?.point)
    motion.show(at: target, screen: screen, animation: .slide, now: 40.1)
    #expect(motion.step(now: 40.1)?.point == first?.point)
    #expect(motion.step(now: 41)?.point == target)
    motion.hide(animation: .none, now: 41)
    #expect(motion.step(now: 41) == nil)
    config.slideDuration = 15
    motion.show(at: target, screen: screen, animation: .slide, now: 50, configuration: config)
    #expect(motion.step(now: 64.99) != nil && motion.isAnimating)
    #expect(motion.step(now: 65)?.point == target && !motion.isAnimating)
    motion.show(
      at: target, screen: screen, animation: AnimationIdentifier(rawValue: "missing"), now: 66)
    #expect(motion.step(now: 66)?.point == target && !motion.isAnimating)
  }

  @Test(arguments: [AnimationIdentifier.slide, .tumble, .none])
  func presentationSettlesAndFollowsTarget(_ animation: AnimationIdentifier) {
    var motion = PresentationMotion()
    #expect(motion.step(now: 0) == nil)
    motion.hide(animation: .slide, now: 0)
    #expect(motion.step(now: 0) == nil)
    motion.show(at: target, screen: screen, animation: animation, now: 10)
    let initial = motion.current.point
    #expect(motion.step(now: 9)?.point == (animation == .none ? target : initial))
    #expect(motion.step(now: 12)?.point == target && !motion.isAnimating)
    motion.target.x += 100
    #expect(motion.step(now: 13)?.point == motion.target)
  }

  @Test(arguments: [AnimationIdentifier.slide, .none])
  func interruptionAndRepeatedHidePreserveDeadline(_ animation: AnimationIdentifier) {
    var motion = PresentationMotion()
    motion.show(at: target, screen: screen, animation: .tumble, now: 0)
    let initial = motion.step(now: 0.2)?.point
    motion.hide(animation: animation, now: 0.2)
    motion.hide(animation: .slide, now: 0.3)
    #expect(motion.step(now: 0.2)?.point == (animation == .none ? nil : initial))
    #expect(motion.step(now: 0.46) == nil && !motion.isAnimating)
  }

  @Test
  func unsafePluginPosesTerminateImmediately() throws {
    for bad in [
      Pose(point: CGPoint(x: Double.nan, y: 0)), Pose(point: target, squash: 0),
      Pose(point: target, angle: .infinity), Pose(point: target, opacity: 2),
      Pose(point: CGPoint(x: 999_999, y: 0)),
    ] {
      var registry = AnimationRegistry()
      try registry.register(UnsafeAnimation(descriptor: descriptor(), pose: bad))
      var motion = PresentationMotion()
      motion.show(
        at: target, screen: screen, animation: AnimationIdentifier(rawValue: "test.fade"), now: 0,
        registry: registry)
      #expect(motion.step(now: 0.1)?.point == target)
      #expect(!motion.isAnimating)
    }
  }
}

extension AnimationPluginTests {
  @Test
  func legacySettingsAndPluginSelectionsRoundTrip() throws {
    let config = try JSONDecoder().decode(
      Configuration.self,
      from: Data(
        #"{"entryAnimation":"test.fade","slideDuration":0.7,"dismissDuration":0.4,"tumbleDuration":2,"entrySettings":{"test.fade":{"duration":0.9,"bounce":false,"direction":"down"}}}"#
          .utf8))
    #expect(config.settings(for: "slide", stage: .entry)["duration"] == .number(0.7))
    #expect(config.settings(for: "slide", stage: .dismissal)["duration"] == .number(0.4))
    #expect(config.settings(for: "tumble", stage: .entry)["duration"] == .number(2))
    #expect(config.settings(for: "test.fade", stage: .entry)["bounce"] == .toggle(false))
    let next = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    #expect(config.isValid && next.isValid)
    #expect(next.entrySettings == config.entrySettings)
    #expect(next.entryAnimation.rawValue == "test.fade")
    var immediate = next
    immediate.entryAnimation = .slide
    immediate.dismissAnimation = .none
    let wire = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(immediate)) as? [String: Any])
    #expect(wire["entryAnimation"] as? String == "slide")
    #expect(wire["dismissAnimation"] as? String == "none")
    var invalid = config
    invalid.entryAnimation = AnimationIdentifier(rawValue: "INVALID")
    #expect(!invalid.isValid)
  }

  @Test
  func topEntryAnchorsToItsDisplayEvenWhenInterrupted() throws {
    let manifest = #"""
      {"version":1,"descriptor":{"id":"test.top","name":"Top","stages":["entry"],
      "settings":[{"id":"duration","name":"Duration","kind":"number","defaultValue":1,"minimum":0.1,"maximum":15}]},
      "keyframes":[
      {"time":0,"curve":"linear","travel":1,"x":0,"y":{"binding":"screenTopOffset"},"angle":0,"squash":1,"opacity":1},
      {"time":1,"curve":"easeOut","travel":1,"x":0,"y":0,"angle":0,"squash":1,"opacity":1}]}
      """#
    let plugin = try KeyframeAnimation.decode(Data(manifest.utf8))
    for top in [-1080.0, 0, 2160] {
      let screen = CGRect(x: -1920, y: top - 1080, width: 1920, height: 1080)
      let final = CGRect(x: -900, y: top - 1130, width: 128, height: 128)
      let context = AnimationContext(
        stage: .entry, finalFrame: final, screen: screen,
        initial: Pose(point: CGPoint(x: -900, y: top - 600)), badge: "4")
      #expect(abs(plugin.frame(in: context, progress: 0, settings: [:]).point.y - top) < 0.000001)
      #expect(plugin.frame(in: context, progress: 1, settings: [:]).point == final.origin)
    }
  }

  @Test
  func catalogInstallsAndRemovesPlugins() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = AnimationCatalog(root: root)
    catalog.reload()
    let source = root.appendingPathComponent("source.json")
    try JSONEncoder().encode(plugin()).write(to: source)
    let installed = try catalog.install(source)
    #expect(installed.descriptor.id == "test.fade")
    catalog.reload()
    #expect(catalog.errors.isEmpty)
    #expect(catalog.registry.plugin(id: "test.fade", stage: .entry) != nil)
    #expect(throws: CocoaError.self) { try catalog.install(source) }
    #expect(catalog.installed["slide"] == nil)
    #expect(throws: CocoaError.self) { try catalog.remove("slide") }
    #expect(throws: CocoaError.self) { try catalog.remove("../source") }
    let file = try #require(catalog.installed["test.fade"])
    let renamed = file.deletingLastPathComponent().appendingPathComponent("renamed.json")
    try FileManager.default.moveItem(at: file, to: renamed)
    catalog.reload()
    try catalog.remove("test.fade")
    #expect(!FileManager.default.fileExists(atPath: renamed.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(catalog.installed.isEmpty)
    #expect(catalog.registry.plugin(id: "test.fade", stage: .entry) == nil)
    _ = try catalog.install(source)
    try Data("bad".utf8).write(to: catalog.directory.appendingPathComponent("bad.json"))
    catalog.reload()
    #expect(catalog.errors.count == 1)
    #expect(catalog.registry.plugin(id: "test.fade", stage: .entry) != nil)
    try Data(repeating: 0, count: 65_537).write(to: source)
    #expect(throws: CocoaError.self) { try catalog.install(source) }
    try FileManager.default.removeItem(at: catalog.directory)
    catalog.reload()
    #expect(
      catalog.errors.isEmpty && catalog.registry.plugin(id: "test.fade", stage: .entry) == nil)
    try Data().write(to: catalog.directory)
    catalog.reload()
    #expect(!catalog.errors.isEmpty)
    #expect(catalog.registry.plugin(id: "slide", stage: .dismissal) != nil)
  }
}

private struct UnsafeAnimation: AnimationPlugin {
  let descriptor: AnimationDescriptor
  let pose: Pose
  func start(in context: AnimationContext) -> Pose { context.initial }
  func frame(in context: AnimationContext, progress: Double, settings: [String: AnimationValue])
    -> Pose
  { pose }
}
