import Foundation
import Testing

@testable import DockPeekRuntime

struct ApplicationProbeTests {
  private func fixture() async throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bundle = root.appendingPathComponent("Probe.app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(
      at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleExecutable": "fixture-probe",
      "CFBundleIdentifier": "test.probe.\(UUID().uuidString)",
      "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSUIElement": true,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
    let source = root.appendingPathComponent("probe.c")
    try Data(
      """
      #include <stdio.h>
      #include <signal.h>
      #include <string.h>
      #include <unistd.h>
      int main(int argc, char **argv) {
        if (argc > 3) {
          FILE *file = fopen(argv[2], "w");
          if (!file) return 1;
          fprintf(file, "%d", getpid()); fclose(file);
        }
        if (argc > 1 && strcmp(argv[1], "hang") == 0) {
          signal(SIGTERM, SIG_IGN);
          for (;;) usleep(100000);
        }
        puts("snapshot"); return 0;
      }
      """.utf8
    ).write(to: source)
    let runner = ProcessRunner()
    _ = try await runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/clang"),
      arguments: [source.path, "-o", contents.appendingPathComponent("MacOS/fixture-probe").path],
      output: root.appendingPathComponent("compile.log"), timeout: .seconds(30))
    _ = try await runner.run(
      executable: URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["--force", "--sign", "-", bundle.path],
      output: root.appendingPathComponent("sign.log"))
    return bundle
  }

  private func ready(_ url: URL) async throws -> pid_t {
    for _ in 0..<400 {
      if let text = try? String(contentsOf: url, encoding: .utf8), let pid = pid_t(text) {
        return pid
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw CocoaError(.fileReadUnknown)
  }

  @Test
  func appLaunchCapturesOutputAndReleasesItsProcess() async throws {
    let bundle = try await fixture()
    let root = bundle.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("output")
    let pidFile = root.appendingPathComponent("pid")
    let probe = ApplicationProbe()
    try await probe.run(
      bundle: bundle, arguments: ["normal", pidFile.path], output: output, timeout: .seconds(5))
    #expect(try String(contentsOf: output, encoding: .utf8) == "snapshot\n")
    let pid = try await ready(pidFile)
    #expect(kill(pid, 0) == -1)
  }

  @Test(arguments: [false, true])
  func timeoutAndCancellationStopTheAppAndPermitReuse(cancel: Bool) async throws {
    let bundle = try await fixture()
    let root = bundle.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("output")
    let pidFile = root.appendingPathComponent("pid")
    let probe = ApplicationProbe()
    let unrelatedRunner = ProcessRunner()
    let unrelatedPIDFile = root.appendingPathComponent("unrelated-pid")
    let unrelated = Task {
      try await unrelatedRunner.run(
        executable: bundle.appendingPathComponent("Contents/MacOS/fixture-probe"),
        arguments: ["hang", unrelatedPIDFile.path, "unrelated"],
        output: root.appendingPathComponent("unrelated-output"), timeout: .seconds(20))
    }
    do {
      let unrelatedPID = try await ready(unrelatedPIDFile)
      let task = Task {
        try await probe.run(
          bundle: bundle, arguments: ["hang", pidFile.path], output: output,
          timeout: cancel ? .seconds(10) : .seconds(2))
      }
      let pid: pid_t
      do { pid = try await ready(pidFile) } catch {
        task.cancel()
        _ = try? await task.value
        throw error
      }
      defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
      await #expect(throws: ProcessFailure.alreadyRunning) {
        try await probe.run(
          bundle: bundle, output: root.appendingPathComponent("second"), timeout: .seconds(5))
      }
      if cancel { task.cancel() }
      if cancel {
        await #expect(throws: CancellationError.self) { try await task.value }
      } else {
        await #expect(throws: ProcessFailure.timedOut) { try await task.value }
      }
      #expect(kill(pid, 0) == -1)
      #expect(kill(unrelatedPID, 0) == 0)
      try await probe.run(
        bundle: bundle, arguments: ["normal"], output: output, timeout: .seconds(5))
      #expect(try String(contentsOf: output, encoding: .utf8) == "snapshot\n")
    } catch {
      unrelated.cancel()
      _ = try? await unrelated.value
      throw error
    }
    unrelated.cancel()
    _ = try? await unrelated.value
  }
}
