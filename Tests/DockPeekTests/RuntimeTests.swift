import DockPeekRuntime
import Foundation
import Testing

struct RuntimeTests {
  private func temporary() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func ready(_ output: URL) async throws {
    for _ in 0..<200 {
      if (try? String(contentsOf: output, encoding: .utf8))?.contains("ready") == true { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw CocoaError(.fileReadUnknown)
  }
  @Test
  func subprocessSuccessExitAndLaunchFailure() async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("output")
    let runner = ProcessRunner()
    #expect(
      try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/printf"),
        arguments: ["hello"], output: output) == 0)
    #expect(try String(contentsOf: output, encoding: .utf8) == "hello")
    await #expect(throws: ProcessFailure.exit(7)) {
      try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 7"], output: output)
    }
    await #expect(throws: (any Error).self) {
      try await runner.run(executable: root.appendingPathComponent("missing"), output: output)
    }
    await #expect(throws: (any Error).self) {
      try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        output: root.appendingPathComponent("missing/out"))
    }
  }
  @Test
  func timeoutKillsAnUncooperativeChildAndRunnerCanBeReused() async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = ProcessRunner()
    let start = ContinuousClock.now
    await #expect(throws: ProcessFailure.timedOut) {
      try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "trap '' TERM; exec /bin/sleep 20"],
        output: root.appendingPathComponent("output"),
        timeout: .milliseconds(100))
    }
    #expect(start.duration(to: .now) < .seconds(3))
    #expect(
      try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/true"),
        output: root.appendingPathComponent("output")) == 0)
  }
  @Test
  func cancellationReapsChildAndRejectsConcurrentLaunches() async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("output")
    let runner = ProcessRunner()
    let task = Task {
      try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo ready; exec /bin/sleep 20"], output: output)
    }
    try await ready(output)
    await #expect(throws: ProcessFailure.alreadyRunning) {
      try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/true"),
        output: root.appendingPathComponent("second"))
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(
      try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/true"), output: output) == 0)
    let cancelled = Task {
      try Task.checkCancellation()
      return try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), output: output)
    }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
  }
  @Test
  func lockRejectsDuplicateOwnershipAndReleasesOnDeinit() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("worker.lock")
    func rejectDuplicate() throws {
      let first = try WorkerLock(url: url)
      _ = withExtendedLifetime(first) {
        #expect(throws: POSIXError.self) { try WorkerLock(url: url) }
      }
    }
    try rejectDuplicate()
    let next = try WorkerLock(url: url)
    withExtendedLifetime(next) {}
    #expect(throws: POSIXError.self) {
      try WorkerLock(url: root.appendingPathComponent("missing/lock"))
    }
  }
  @Test
  func isolatedRuntimePathsRequireAnExplicitMarker() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(!RuntimePaths.isVerification(root))
    try Data().write(to: root.appendingPathComponent(".dockpeek-verification"))
    #expect(RuntimePaths.root(arguments: ["app", "--verify-root", root.path]).path == root.path)
    #expect(
      RuntimePaths.root(arguments: ["app", "--verify-root"]).lastPathComponent == "Dock Peek")
    #expect(RuntimePaths.root(arguments: ["app"]).lastPathComponent == "Dock Peek")
  }
}
