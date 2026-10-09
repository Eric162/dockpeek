import Foundation
import ServiceManagement
import Testing

@testable import DockPeekSettings

@MainActor
private final class TestLoginManager: LoginManaging {
  var status = SMAppService.Status.notRegistered
  var fail = false
  var registrations = 0
  var approvals = 0
  func register() throws {
    registrations += 1
    if fail { throw CocoaError(.featureUnsupported) }
    status = .enabled
  }
  func unregister() throws {
    if fail { throw CocoaError(.featureUnsupported) }
    status = .notRegistered
  }
  func migrateLegacyAgent() throws { if fail { throw CocoaError(.featureUnsupported) } }
  func openApprovalSettings() { approvals += 1 }
}

@MainActor
private final class TestLauncher: WorkerLaunching {
  var workerURL = URL(fileURLWithPath: "/Missing/Worker")
  var existingPID: pid_t?
  var launches = 0
  var fail = false
  func workerPID(root: URL) -> pid_t? { existingPID }
  func launch(root: URL) throws {
    if fail { throw CocoaError(.fileNoSuchFile) }
    launches += 1
    existingPID = 123
  }
}

@MainActor
struct BackgroundTests {
  private func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Contents/Resources/Dock Tile Probe.app"),
      withIntermediateDirectories: true)
    return root
  }
  @Test
  func workerPreparationIsIdempotentAndPreservesConfigAndProbe() throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let launcher = TestLauncher()
    let service = BackgroundService(
      root: root, login: TestLoginManager(), launcher: launcher, bundle: root)
    try service.ensureWorker()
    let config = try Data(contentsOf: root.appendingPathComponent("peek-config.json"))
    let sentinel = root.appendingPathComponent(".build/Dock Tile Probe.app/authorized")
    try Data("preserve".utf8).write(to: sentinel)
    try service.ensureWorker()
    #expect(launcher.launches == 1)
    #expect(try Data(contentsOf: root.appendingPathComponent("peek-config.json")) == config)
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "preserve")
  }
  @Test
  func stalePIDAndUnrelatedLivePIDNeverSuppressLaunch() throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let launcher = BundledWorkerLauncher(bundle: root)
    for pid in ["not-a-pid", "-1", "2147483647", String(getpid())] {
      try Data(pid.utf8).write(to: root.appendingPathComponent("worker.pid"))
      #expect(launcher.workerPID(root: root) == nil)
    }
    #expect(throws: (any Error).self) { try launcher.launch(root: root) }
  }
  @Test
  func registrationApprovalAndUnregistrationHaveExplicitResults() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let login = TestLoginManager()
    let launcher = TestLauncher()
    let service = BackgroundService(root: root, login: login, launcher: launcher, bundle: root)
    await service.setLaunchAtLogin(true)
    #expect(service.launchAtLogin)
    #expect(login.registrations == 1)
    await service.setLaunchAtLogin(true)
    #expect(login.registrations == 1)
    await service.setLaunchAtLogin(false)
    #expect(!service.launchAtLogin)
    #expect(!service.busy)
    login.status = .requiresApproval
    launcher.existingPID = nil
    await service.setLaunchAtLogin(true)
    #expect(login.approvals == 1)
    #expect(service.requiresApproval)
    try service.ensureWorker()
    #expect(launcher.launches == 1)
    service.busy = true
    await service.setLaunchAtLogin(false)
    #expect(login.status == .requiresApproval)
  }
  @Test
  func launchAndLoginFailuresAreReportedWithoutSavingSuccess() async throws {
    let root = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let login = TestLoginManager()
    let launcher = TestLauncher()
    let service = BackgroundService(root: root, login: login, launcher: launcher, bundle: root)
    launcher.fail = true
    service.prepare()
    #expect(service.message.hasPrefix("Could not start"))
    login.fail = true
    await service.setLaunchAtLogin(true)
    #expect(service.message.hasPrefix("Could not change"))
    #expect(!service.busy)
    login.status = .enabled
    await service.setLaunchAtLogin(false)
    #expect(service.launchAtLogin)
    #expect(service.message.hasPrefix("Could not change"))
    await service.migrateLegacyAgent()
    #expect(service.message.hasPrefix("Could not migrate"))
  }
}
