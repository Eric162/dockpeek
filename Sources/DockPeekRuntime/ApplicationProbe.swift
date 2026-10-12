import Darwin
import Foundation

/// Launches a probe with its own macOS app identity and stops only this invocation on failure.
actor ApplicationProbe {
  private let runner = ProcessRunner()
  private var running = false

  func run(bundle: URL, arguments: [String] = [], output: URL, timeout: Duration) async throws {
    guard !running else { throw ProcessFailure.alreadyRunning }
    running = true
    defer { running = false }
    try Task.checkCancellation()
    guard let executable = Bundle(url: bundle)?.executableURL else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let deadline = ContinuousClock.now + timeout
    let marker = "--dockpeek-invocation=\(UUID().uuidString)"
    let launcherOutput = output.deletingLastPathComponent().appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: launcherOutput) }
    try Data().write(to: output)
    do {
      do {
        _ = try await runner.run(
          executable: URL(fileURLWithPath: "/usr/bin/open"),
          arguments: [
            "-W", "-n", "-g", "-j", "--stdout", output.path, "--stderr", "/dev/null",
            bundle.path, "--args",
          ] + arguments + [marker], output: launcherOutput, timeout: timeout)
      } catch let error as ProcessFailure {
        // open can report a wait failure when a short-lived app has already finished.
        let hasOutput = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0
        guard case .exit = error,
          hasOutput || !ownedPIDs(executable: executable, marker: marker).isEmpty
        else { throw error }
      }
      while !ownedPIDs(executable: executable, marker: marker).isEmpty {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ProcessFailure.timedOut }
        try await Task.sleep(for: .milliseconds(20))
      }
    } catch {
      // Cleanup must finish even when the caller's task has already been cancelled.
      let cleanup = Task.detached {
        await self.stopOwnedProbe(executable: executable, marker: marker)
      }
      await cleanup.value
      throw error
    }
  }

  private func stopOwnedProbe(executable: URL, marker: String) async {
    // Keep observing briefly for an app whose launch was still completing when open was stopped.
    for attempt in 0..<20 {
      for pid in ownedPIDs(executable: executable, marker: marker) {
        kill(pid, attempt < 5 ? SIGTERM : SIGKILL)
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  private func ownedPIDs(executable: URL, marker: String) -> [pid_t] {
    guard let resolved = realpath(executable.path, nil) else { return [] }
    defer { free(resolved) }
    let expectedPath = String(cString: resolved)
    let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
    guard bytes > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.stride + 32)
    let length = Int32(pids.count * MemoryLayout<pid_t>.stride)
    let actual = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, length)
    guard actual > 0 else { return [] }
    return pids.prefix(Int(actual) / MemoryLayout<pid_t>.stride).filter { pid in
      var path = [CChar](repeating: 0, count: 4096)
      guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
      let actualPath = String(
        decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      return actualPath == expectedPath && hasArgument(marker, pid: pid)
    }
  }

  private func hasArgument(_ argument: String, pid: pid_t) -> Bool {
    var query = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&query, 3, nil, &size, nil, 0) == 0, size > 4, size <= 1024 * 1024 else {
      return false
    }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctl(&query, 3, &bytes, &size, nil, 0) == 0 else { return false }
    let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard count > 0 else { return false }
    var index = 4
    // The kernel returns argc, executable path, padding, then the argv strings.
    while index < size && bytes[index] != 0 { index += 1 }
    while index < size && bytes[index] == 0 { index += 1 }
    for _ in 0..<count {
      let start = index
      while index < size && bytes[index] != 0 { index += 1 }
      if String(decoding: bytes[start..<index], as: UTF8.self) == argument { return true }
      guard index < size else { return false }
      index += 1
    }
    return false
  }
}
