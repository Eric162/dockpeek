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
