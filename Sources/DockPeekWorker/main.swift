import AppKit
import DockPeekRuntime

@Sendable func log(_ text: String) {
  print(text)
  fflush(stdout)
}

let args = Array(CommandLine.arguments.dropFirst())
let installed =
  args.contains("--installed") || Bundle.main.bundleIdentifier == "local.dock-peek.worker"
let root =
  installed || args.contains("--verify-root")
  ? RuntimePaths.root()
  : URL(fileURLWithPath: args.first ?? FileManager.default.currentDirectoryPath)
let configPath = args.firstIndex(of: "--config")
  .flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
let configURL =
  configPath.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("peek-config.json")
let allowed: Set<String>? =
  installed || args.contains("--verify-root") || (args.count > 1 && args[1] == "-")
  ? nil
  : Set((args.count > 1 ? args[1] : "com.openai.codex").split(separator: ",").map(String.init))
let duration =
  installed || args.contains("--verify-root") ? 0 : (args.count > 2 ? Double(args[2]) ?? 45 : 45)
var workerLock: WorkerLock?
do {
  try FileManager.default.createDirectory(
    at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
  workerLock = try WorkerLock(url: root.appendingPathComponent("worker.lock"))
  try String(getpid()).write(
    to: root.appendingPathComponent("worker.pid"), atomically: true, encoding: .utf8)
} catch let error as POSIXError where error.code == .EWOULDBLOCK { exit(0) } catch {
  fputs("Cannot start worker: \(error)\n", stderr)
  exit(1)
}
if installed {
  freopen(root.appendingPathComponent("overlay.log").path, "a", stdout)
  freopen(root.appendingPathComponent("overlay-error.log").path, "a", stderr)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = WorkerController(
  root: root, configURL: configURL, demo: args.contains("--demo"), allowedOverride: allowed)
@MainActor
final class WorkerDelegate: NSObject, NSApplicationDelegate {
  private var shutdownRequested = false
  private var drained = false
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if drained { return .terminateNow }
    if !shutdownRequested {
      shutdownRequested = true
      Task {
        await controller.stop()
        try? FileManager.default.removeItem(at: root.appendingPathComponent("worker.pid"))
        drained = true
        sender.terminate(nil)
      }
    }
    // Returning promptly lets the main queue run the async drain. AppKit's
    // terminateLater nested event loop can otherwise block that same queue.
    return .terminateCancel
  }
}
let delegate = WorkerDelegate()
app.delegate = delegate
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { app.terminate(nil) }
termination.resume()
log("Dock Peek; root=\(root.path)")
controller.start()
if duration > 0 {
  DispatchQueue.main.asyncAfter(deadline: .now() + duration) { app.terminate(nil) }
}
withExtendedLifetime((delegate, termination, workerLock)) { app.run() }
