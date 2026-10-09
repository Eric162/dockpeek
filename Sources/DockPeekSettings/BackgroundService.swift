import Darwin
import DockPeekCore
import DockPeekRuntime
import ServiceManagement

@MainActor
protocol LoginManaging {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() async throws
  func migrateLegacyAgent() async throws
  func openApprovalSettings()
}

@MainActor
struct SystemLoginManager: LoginManaging {
  var status: SMAppService.Status { SMAppService.mainApp.status }
  func register() throws { try SMAppService.mainApp.register() }
  func unregister() async throws { try await SMAppService.mainApp.unregister() }
  func migrateLegacyAgent() async throws {
    let legacy = SMAppService.agent(plistName: "local.dock-peek.worker.plist")
    if legacy.status != .notRegistered { try await legacy.unregister() }
  }
  func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}

// Verification launches use isolated storage and never alter Login Items.
@MainActor
struct VerificationLoginManager: LoginManaging {
  var status: SMAppService.Status { .notRegistered }
  func register() throws { throw CocoaError(.featureUnsupported) }
  func unregister() throws {}
  func migrateLegacyAgent() throws {}
  func openApprovalSettings() {}
}

@MainActor
protocol WorkerLaunching {
  var workerURL: URL { get }
  func workerPID(root: URL) -> pid_t?
  func launch(root: URL) throws
}

@MainActor
struct BundledWorkerLauncher: WorkerLaunching {
  let bundle: URL
  var workerURL: URL {
    bundle.appendingPathComponent(
      "Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker")
  }
  func workerPID(root: URL) -> pid_t? {
    guard
      let text = try? String(
        contentsOf: root.appendingPathComponent("worker.pid"), encoding: .utf8),
      let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
      kill(pid, 0) == 0
    else { return nil }
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
      String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        == workerURL.path
    else { return nil }
    return pid
  }
  func launch(root: URL) throws {
    let process = Process()
    process.executableURL = workerURL
    process.arguments = ["--installed"]
    if RuntimePaths.isVerification(root) {
      process.arguments = ["--installed", "--verify-root", root.path]
    }
    let output = try logHandle(root.appendingPathComponent("overlay.log"))
    defer { try? output.close() }
    let errors = try logHandle(root.appendingPathComponent("overlay-error.log"))
    defer { try? errors.close() }
    process.standardOutput = output
    process.standardError = errors
    process.standardInput = FileHandle.nullDevice
    try process.run()
  }
  private func logHandle(_ url: URL) throws -> FileHandle {
    if !FileManager.default.fileExists(atPath: url.path) {
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
      }
    }
    let handle = try FileHandle(forWritingTo: url)
    do { try handle.seekToEnd() } catch {
      try? handle.close()
      throw error
    }
    return handle
  }
}

@MainActor
final class BackgroundService: ObservableObject {
  @Published var launchAtLogin = false
  @Published var requiresApproval = false
  @Published var busy = false
  @Published var message = ""
  let root: URL
  private let login: any LoginManaging
  private let launcher: any WorkerLaunching
  private let bundle: URL

  init(
    root: URL, login: (any LoginManaging)? = nil,
    launcher: (any WorkerLaunching)? = nil, bundle: URL = Bundle.main.bundleURL
  ) {
    self.root = root
    self.bundle = bundle
    self.login =
      login
      ?? (RuntimePaths.isVerification(root)
        ? VerificationLoginManager() : SystemLoginManager())
    self.launcher = launcher ?? BundledWorkerLauncher(bundle: bundle)
    refresh()
  }
  func migrateLegacyAgent() async {
    do { try await login.migrateLegacyAgent() } catch {
      message = "Could not migrate background service: \(error.localizedDescription)"
    }
  }
  func refresh() {
    launchAtLogin = login.status == .enabled || login.status == .requiresApproval
    requiresApproval = login.status == .requiresApproval
  }
  func ensureWorker() throws {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
    let probe = root.appendingPathComponent(".build/Dock Tile Probe.app")
    if !FileManager.default.fileExists(atPath: probe.path) {
      try FileManager.default.copyItem(
        at: bundle.appendingPathComponent("Contents/Resources/Dock Tile Probe.app"), to: probe)
    }
    let configURL = root.appendingPathComponent("peek-config.json")
    if !FileManager.default.fileExists(atPath: configURL.path) {
      try JSONEncoder().encode(Configuration()).write(to: configURL, options: .atomic)
    }
    refresh()
    guard launcher.workerPID(root: root) == nil, !requiresApproval else { return }
    try launcher.launch(root: root)
  }
  func prepare() {
    do { try ensureWorker() } catch {
      message = "Could not start Dock Peek: \(error.localizedDescription)"
    }
  }
  func setLaunchAtLogin(_ enabled: Bool) async {
    guard !busy else { return }
    busy = true
    defer {
      busy = false
      refresh()
    }
    do {
      if enabled {
        if login.status == .enabled {
          try ensureWorker()
          return
        }
        if login.status == .requiresApproval {
          login.openApprovalSettings()
          return
        }
        try login.register()
      } else if login.status != .notRegistered {
        try await login.unregister()
      }
      try ensureWorker()
      message = "Saved."
    } catch {
      message = "Could not change login setting: \(error.localizedDescription)"
      try? ensureWorker()
    }
  }
}
