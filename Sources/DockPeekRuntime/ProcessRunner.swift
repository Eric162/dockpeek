import Foundation

public enum ProcessFailure: Error, Equatable {
  case alreadyRunning, timedOut
  case exit(Int32)
  case oversizedOutput
}

/// Owns one child until it exits, including cancellation and timeout cleanup.
public actor ProcessRunner {
  private var process: Process?
  public init() {}

  public func run(
    executable: URL, arguments: [String] = [], output: URL,
    timeout: Duration = .seconds(3)
  ) async throws -> Int32 {
    guard process == nil else { throw ProcessFailure.alreadyRunning }
    try Task.checkCancellation()
    guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    let child = Process()
    child.executableURL = executable
    child.arguments = arguments
    child.standardOutput = handle
    child.standardError = FileHandle.nullDevice
    child.standardInput = FileHandle.nullDevice
    try child.run()
    process = child
    defer { process = nil }
    let deadline = ContinuousClock.now + timeout
    do {
      while child.isRunning {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ProcessFailure.timedOut }
        try await Task.sleep(for: .milliseconds(20))
      }
    } catch {
      // A detached cleanup remains runnable after the caller is cancelled.
      await Task.detached { await self.drain() }.value
      throw error
    }
    guard child.terminationStatus == 0 else { throw ProcessFailure.exit(child.terminationStatus) }
    return child.terminationStatus
  }

  private func drain() async {
    guard let process, process.isRunning else { return }
    process.terminate()
    let deadline = ContinuousClock.now + .milliseconds(250)
    while process.isRunning {
      if ContinuousClock.now >= deadline { kill(process.processIdentifier, SIGKILL) }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}
