import Foundation

public enum RuntimePaths {
  public static func isVerification(_ root: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: root.appendingPathComponent(".dockpeek-verification").path)
  }

  public static func root(arguments: [String] = CommandLine.arguments) -> URL {
    if let index = arguments.firstIndex(of: "--verify-root"), arguments.indices.contains(index + 1)
    {
      let root = URL(fileURLWithPath: arguments[index + 1])
      guard isVerification(root) else {
        fatalError("Verification root must contain .dockpeek-verification")
      }
      return root
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Dock Peek")
  }
}
