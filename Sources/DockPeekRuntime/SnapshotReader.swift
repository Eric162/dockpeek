import Foundation

public actor SnapshotReader {
  private let runner = ProcessRunner()
  public init() {}

  public func read(root: URL, probe: URL, timeout: Duration = .seconds(3)) async throws -> String {
    let snapshot = root.appendingPathComponent(".build/peek-snapshot-\(getpid()).txt")
    let arguments = RuntimePaths.isVerification(root) ? ["--verify-root", root.path] : []
    _ = try await runner.run(
      executable: probe, arguments: arguments, output: snapshot, timeout: timeout)
    let size = try snapshot.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 2 * 1024 * 1024 else { throw ProcessFailure.oversizedOutput }
    let text = try String(contentsOf: snapshot, encoding: .utf8)
    guard !text.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return text
  }
}
