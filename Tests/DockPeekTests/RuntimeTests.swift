import DockPeekRuntime
import Foundation
import Testing

struct RuntimeTests {
  private func temporary() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func ready(_ output: URL) async throws -> pid_t {
    for _ in 0..<200 {
      if let text = try? String(contentsOf: output, encoding: .utf8),
        let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
      {
        return pid
      }
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
  @Test(arguments: [false, true])
  func timeoutAndCancellationReapChildRejectOverlapAndPermitReuse(cancel: Bool) async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("output")
    let runner = ProcessRunner()
    let start = ContinuousClock.now
    let task = Task {
      try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "trap '' TERM; echo $$; exec /bin/sleep 20"], output: output,
        timeout: cancel ? .seconds(20) : .milliseconds(100))
    }
    let pid: pid_t
    do { pid = try await ready(output) } catch {
      task.cancel()
      _ = try? await task.value
      throw error
    }
    defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
    if cancel {
      await #expect(throws: ProcessFailure.alreadyRunning) {
        try await runner.run(
          executable: URL(fileURLWithPath: "/usr/bin/true"),
          output: root.appendingPathComponent("second"))
      }
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
    } else {
      await #expect(throws: ProcessFailure.timedOut) { try await task.value }
      #expect(start.duration(to: .now) < .seconds(3))
    }
    #expect(kill(pid, 0) == -1)
    #expect(
      try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), output: output) == 0)
    let gate = AsyncStream<Void>.makeStream()
    let cancelledOutput = root.appendingPathComponent("cancelled-output")
    let cancelled = Task {
      var iterator = gate.stream.makeAsyncIterator()
      _ = await iterator.next()
      return try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/true"), output: cancelledOutput)
    }
    cancelled.cancel()
    gate.continuation.finish()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(!FileManager.default.fileExists(atPath: cancelledOutput.path))
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
  func runtimePathsRecognizeMarkedOverridesAndKeepDefaultFallbacks() throws {
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
