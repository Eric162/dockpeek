import AppKit
import DockPeekCore
import Testing

@testable import DockPeekSettings

struct SettingsTests {
  @MainActor
  @Test
  func testSelectionPersistenceAndTemporaryTestDoesNotChangeSavedSettings() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("peek-config.json")
    try Data("{}".utf8).write(to: url)
    let model = SettingsModel(root: root)
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
    let reloaded = SettingsModel(root: root)
    #expect(reloaded.config.peekFraction == 0.4)
    #expect(reloaded.config.applicationPaths[id] == app.path)
    #expect(!(reloaded.config.allowedApps.contains(id)))
    let saved = try Data(contentsOf: url)
    model.testPeek(bundleIdentifier: "local.dock-peek.settings", applicationPath: "/Dock Peek.app")
    let request = try JSONDecoder().decode(
      PeekTestRequest.self,
      from: Data(contentsOf: root.appendingPathComponent("test-request.json")))
    #expect(request.isActive)
    #expect(request.bundleIdentifier == "local.dock-peek.settings")
    #expect(try Data(contentsOf: url) == saved)
    #expect(!(model.config.allowedApps.contains(request.bundleIdentifier)))
    model.config.peekFraction = 2
    model.apply()
    #expect(model.error)
    #expect(try Data(contentsOf: url) == saved)
  }
}
