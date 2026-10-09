import Foundation

public enum ProcessFailure: Error, Equatable {
  case alreadyRunning, timedOut
  case exit(Int32)
  case oversizedOutput
}

/// Owns one child. Cancellation and timeouts reap it before completing the call.
public actor ProcessRunner {
  private var process: Process?
  private var requestID: UUID?
  private var continuation: CheckedContinuation<Int32, any Error>?
  private var timeoutTask: Task<Void, Never>?
  private var killTask: Task<Void, Never>?
  private var failure: (any Error)?

  public init() {}

  public func run(
    executable: URL, arguments: [String] = [], output: URL,
    timeout: Duration = .seconds(3)
  ) async throws -> Int32 {
    guard process == nil else { throw ProcessFailure.alreadyRunning }
    try Task.checkCancellation()
    let requestID = UUID()
    self.requestID = requestID
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        launch(
          executable: executable, arguments: arguments, output: output, timeout: timeout,
          requestID: requestID)
      }
    } onCancel: {
      Task { await self.stop(with: CancellationError(), requestID: requestID) }
    }
  }

  private func launch(
    executable: URL, arguments: [String], output: URL, timeout: Duration, requestID: UUID
  ) {
    do {
      guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
      }
      let handle = try FileHandle(forWritingTo: output)
      defer { try? handle.close() }
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      process.standardOutput = handle
      process.standardError = FileHandle.nullDevice
      process.standardInput = FileHandle.nullDevice
      process.terminationHandler = { process in
        let status = process.terminationStatus
        Task { await self.finished(status: status, requestID: requestID) }
      }
      self.process = process
      try process.run()
      timeoutTask = Task {
        do { try await Task.sleep(for: timeout) } catch { return }
        self.stop(with: ProcessFailure.timedOut, requestID: requestID)
      }
    } catch { complete(.failure(error)) }
  }

  private func stop(with error: any Error, requestID: UUID) {
    guard self.requestID == requestID, let process, process.isRunning else { return }
    if failure == nil { failure = error }
    process.terminate()
    killTask = Task {
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  private func finished(status: Int32, requestID: UUID) {
    guard self.requestID == requestID else { return }
    if let failure {
      complete(.failure(failure))
    } else if status != 0 {
      complete(.failure(ProcessFailure.exit(status)))
    } else {
      complete(.success(status))
    }
  }

  private func complete(_ result: Result<Int32, any Error>) {
    timeoutTask?.cancel()
    killTask?.cancel()
    timeoutTask = nil
    killTask = nil
    process?.terminationHandler = nil
    process = nil
    requestID = nil
    failure = nil
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(with: result)
  }
}
