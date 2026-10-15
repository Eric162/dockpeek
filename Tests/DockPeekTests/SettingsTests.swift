import DockPeekCore
import AppKit
import Foundation
import Testing

@testable import DockPeekSettings

struct SettingsTests {
  @MainActor
  @Test
  func testSelectionPersistenceAndTemporaryTestDoesNotChangeSavedSettings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("peek-config.json")
    try Data("{}".utf8).write(to: url)
    let model = SettingsModel(root: root)
    #expect(!model.isDirty)
    model.config.allowedApps.reverse()
    #expect(!model.isDirty)
    let initial = model.config
    model.config.peekFraction = 0.75
    #expect(model.isDirty)
    model.config = initial
    #expect(!model.isDirty)
    let app = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    let id = try #require(Bundle(url: app)?.bundleIdentifier)
    model.addApplications([app, app])
    #expect(model.config.allowedApps.filter { $0 == id }.count == 1)
    model.config.allowedApps.removeAll { $0 == id }
    #expect(model.apps.contains { $0.id == id })
    model.config.peekFraction = 0.4
    model.config.enabled = false
    model.apply()
    #expect(!(model.error))
    #expect(model.message == "Saved.")
    #expect(!model.isDirty)
    let reloaded = SettingsModel(root: root)
    #expect(reloaded.config.peekFraction == 0.4)
    #expect(reloaded.config.applicationPaths[id] == app.path)
    #expect(!(reloaded.config.allowedApps.contains(id)))
    let saved = try Data(contentsOf: url)
    model.config.peekFraction = 0.8
    model.config.entryAnimation = .slide
    model.config.entrySettings["slide"] = ["duration": .number(0.7)]
    model.testPeek(bundleIdentifier: "local.dock-peek.settings", applicationPath: "/Dock Peek.app")
    let request = try JSONDecoder().decode(
      PeekTestRequest.self,
      from: Data(contentsOf: root.appendingPathComponent("test-request.json")))
    #expect(request.isActive)
    #expect(request.bundleIdentifier == "local.dock-peek.settings")
    #expect(request.configuration == model.config)
    #expect(model.isDirty)
    #expect(try Data(contentsOf: url) == saved)
    #expect(!(model.config.allowedApps.contains(request.bundleIdentifier)))
    model.config.peekFraction = 2
    let lastRequest = try Data(contentsOf: root.appendingPathComponent("test-request.json"))
    model.testPeek()
    #expect(model.error)
    #expect(try Data(contentsOf: root.appendingPathComponent("test-request.json")) == lastRequest)
    model.apply()
    #expect(model.error)
    #expect(model.isDirty)
    #expect(try Data(contentsOf: url) == saved)
    model.config = reloaded.config
    #expect(!model.isDirty)
    model.config.peekFraction = 0.6
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    model.apply()
    #expect(model.error)
    #expect(model.isDirty)
  }

  @MainActor
  @Test
  func removingAnAnimationPreservesOtherDraftChangesAndUpdatesSavedSelections() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("peek-config.json")
    var saved = Configuration()
    let id = "example.fade"
    saved.entryAnimation = AnimationIdentifier(rawValue: id)
    saved.dismissAnimation = AnimationIdentifier(rawValue: id)
    saved.entrySettings[id] = ["duration": .number(1)]
    saved.dismissalSettings[id] = ["duration": .number(2)]
    try JSONEncoder().encode(saved).write(to: file)
    let model = SettingsModel(root: root)
    let source = URL(fileURLWithPath: "docs/examples/fade.json")
    _ = try model.animations.install(source)
    model.config.peekFraction = 0.8
    model.config.entryAnimation = .tumble
    model.removeAnimation(id)
    #expect(!model.error)
    #expect(model.isDirty)
    #expect(model.config.peekFraction == 0.8)
    #expect(model.config.entryAnimation == .tumble)
    #expect(model.config.dismissAnimation == .slide)
    #expect(model.config.entrySettings[id] == nil && model.config.dismissalSettings[id] == nil)
    let updated = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
    #expect(updated.entryAnimation == .slide && updated.dismissAnimation == .slide)
    #expect(updated.peekFraction == saved.peekFraction)
    #expect(updated.entrySettings[id] == nil && updated.dismissalSettings[id] == nil)
    #expect(model.animations.installed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: source.path))
    let bytes = try Data(contentsOf: file)
    model.removeAnimation("slide")
    #expect(model.error)
    #expect(try Data(contentsOf: file) == bytes)
    _ = try model.animations.install(source)
    let installed = try #require(model.animations.installed[id])
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    model.removeAnimation(id)
    #expect(model.error)
    #expect(FileManager.default.fileExists(atPath: installed.path))
  }

  @MainActor
  @Test
  func copiedAnimationPromptContainsAnInstallableExample() throws {
    let plugin = try KeyframeAnimation.decode(Data(AnimationPrompt.example.utf8))
    #expect(plugin.descriptor.id == "custom.slide")
    #expect(plugin.descriptor.stages == [.entry])
    #expect(AnimationPrompt.text.contains(AnimationPrompt.example))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = SettingsModel(root: root)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    model.copyAnimationPrompt(to: pasteboard)
    #expect(!model.error)
    #expect(pasteboard.string(forType: .string) == AnimationPrompt.text)
  }
}
