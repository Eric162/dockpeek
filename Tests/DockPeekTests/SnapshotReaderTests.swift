import DockPeekRuntime
import Foundation
import Testing

struct SnapshotReaderTests {
  @Test(arguments: ["dock-tile-probe", "DockTileProbe"])
  func readerRejectsEmptyAndOversizedOutputAndReadsValidSnapshots(executableName: String)
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent(".dockpeek-verification"))
    let bundle = root.appendingPathComponent(".build/Dock Tile Probe.app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(
      at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    let info = [
      "CFBundleExecutable": executableName, "CFBundleIdentifier": "test.probe",
      "CFBundlePackageType": "APPL",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
    let executable = contents.appendingPathComponent("MacOS/\(executableName)")
    func script(_ body: String) throws {
      try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: executable)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    let reader = SnapshotReader()
    await #expect(throws: CocoaError.self) {
      try await reader.read(root: root, probeBundle: root.appendingPathComponent("missing.app"))
    }
    try script("printf snapshot")
    #expect(try await reader.read(root: root, probeBundle: bundle) == "snapshot")
    try script("exit 0")
    await #expect(throws: CocoaError.self) {
      try await reader.read(root: root, probeBundle: bundle)
    }
    try script("exec /usr/bin/head -c 2097153 /dev/zero")
    await #expect(throws: ProcessFailure.oversizedOutput) {
      try await reader.read(root: root, probeBundle: bundle)
    }
  }
}
