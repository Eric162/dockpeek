import Darwin
import DockPeekCore
import ServiceManagement

@MainActor
final class BackgroundService: ObservableObject {
  static let plistName = "local.dock-peek.worker.plist"
  @Published var launchAtLogin = false
  @Published var requiresApproval = false
  @Published var busy = false
  @Published var message = ""
  let root: URL
  let service = SMAppService.mainApp
  var workerURL: URL {
    Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker")
  }
  init(root: URL) {
    self.root = root
    refresh()
  }
  func migrateLegacyAgent() async {
    let legacy = SMAppService.agent(plistName: Self.plistName)
    if legacy.status != .notRegistered {
      do { try await legacy.unregister() } catch {
        message = "Could not migrate background service: \(error.localizedDescription)"
      }
    }
  }
  func refresh() {
    launchAtLogin = service.status == .enabled || service.status == .requiresApproval
    requiresApproval = service.status == .requiresApproval
  }
  var workerPID: pid_t? {
    guard
      let text = try? String(
        contentsOf: root.appendingPathComponent("worker.pid"), encoding: .utf8),
      let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), kill(pid, 0) == 0
    else { return nil }
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
      String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        == workerURL.path
    else { return nil }
    return pid
  }
  func ensureWorker() throws {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
    let probe = root.appendingPathComponent(".build/Dock Tile Probe.app")
    if !FileManager.default.fileExists(atPath: probe.path) {
      try FileManager.default.copyItem(
        at: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Dock Tile Probe.app"),
        to: probe)
    }
    let configURL = root.appendingPathComponent("peek-config.json")
    if !FileManager.default.fileExists(atPath: configURL.path) {
      try JSONEncoder().encode(Configuration()).write(to: configURL, options: .atomic)
    }
    refresh()
    guard workerPID == nil, !requiresApproval else { return }
    let process = Process()
    process.executableURL = workerURL
    process.arguments = ["--installed"]
    for name in ["overlay.log", "overlay-error.log"] {
      let path = root.appendingPathComponent(name).path
      if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
      }
    }
    let output = try FileHandle(forWritingTo: root.appendingPathComponent("overlay.log"))
    let errors = try FileHandle(forWritingTo: root.appendingPathComponent("overlay-error.log"))
    try output.seekToEnd()
    try errors.seekToEnd()
    process.standardOutput = output
    process.standardError = errors
    process.standardInput = FileHandle.nullDevice
    try process.run()
    try output.close()
    try errors.close()
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
        if service.status == .enabled {
          try ensureWorker()
          return
        }
        if service.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
          return
        }
        try service.register()
        try ensureWorker()
        message = "Saved."
      } else {
        if service.status != .notRegistered { try await service.unregister() }
        try ensureWorker()
        message = "Saved."
      }
    } catch {
      message = "Could not change login setting: \(error.localizedDescription)"
      try? ensureWorker()
    }
  }
}
