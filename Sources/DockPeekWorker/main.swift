import AppKit
import DockPeekRuntime

@Sendable func log(_ text: String) {
  print(text)
  fflush(stdout)
}

let root = RuntimePaths.root()
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
freopen(root.appendingPathComponent("overlay.log").path, "a", stdout)
freopen(root.appendingPathComponent("overlay-error.log").path, "a", stderr)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = WorkerController(
  root: root)
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
withExtendedLifetime((delegate, termination, workerLock)) { app.run() }
