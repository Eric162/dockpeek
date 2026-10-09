import DockPeekRuntime
import Foundation
import Testing

struct SnapshotReaderTests {
  @Test
  func readerRejectsEmptyAndOversizedOutputAndReadsValidSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("probe")
    func script(_ body: String) throws {
      try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: executable)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    let reader = SnapshotReader()
    try script("printf snapshot")
    #expect(try await reader.read(root: root, probe: executable) == "snapshot")
    try script("exit 0")
    await #expect(throws: CocoaError.self) { try await reader.read(root: root, probe: executable) }
    try script("exec /usr/bin/head -c 2097153 /dev/zero")
    await #expect(throws: ProcessFailure.oversizedOutput) {
      try await reader.read(root: root, probe: executable)
    }
  }
}
