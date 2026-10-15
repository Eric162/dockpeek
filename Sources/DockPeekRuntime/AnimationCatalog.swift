import DockPeekCore
import Foundation

/// Reloads only changed files; each imported manifest has bounded input and complexity.
public final class AnimationCatalog {
  public private(set) var registry = AnimationRegistry()
  public private(set) var errors: [String] = []
  public private(set) var installed: [String: URL] = [:]
  public let directory: URL
  private var fingerprint: [String] = []
  public init(root: URL) {
    directory = root.appendingPathComponent("Animations", isDirectory: true)
  }
  public func reload() {
    do {
      guard FileManager.default.fileExists(atPath: directory.path) else {
        registry = AnimationRegistry()
        installed = [:]
        errors = []
        fingerprint = []
        return
      }
      let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
      )
      .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      let next = try files.map {
        let values = try $0.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return
          "\($0.lastPathComponent):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)"
      }
      guard next != fingerprint else { return }
      fingerprint = next
      registry = AnimationRegistry()
      installed = [:]
      errors = []
      if files.count > 64 { errors.append("Only 64 installed animation plugins are supported.") }
      for file in files.prefix(64) {
        do {
          let plugin = try Self.read(file)
          try registry.register(plugin)
          installed[plugin.descriptor.id] = file
        } catch {
          errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
        }
      }
    } catch {
      registry = AnimationRegistry()
      installed = [:]
      errors = ["Could not load animation plugins: \(error.localizedDescription)"]
      fingerprint = []
    }
  }
  public func remove(_ id: String) throws {
    guard let file = installed[id] else { throw CocoaError(.fileNoSuchFile) }
    try FileManager.default.removeItem(at: file)
    reload()
  }
  public func install(_ file: URL) throws -> KeyframeAnimation {
    let plugin = try Self.read(file)
    var candidate = registry
    try candidate.register(plugin)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(plugin.descriptor.id + ".json")
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw CocoaError(.fileWriteFileExists)
    }
    try JSONEncoder().encode(plugin).write(to: destination, options: .atomic)
    reload()
    return plugin
  }
  private static func read(_ url: URL) throws -> KeyframeAnimation {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true, let size = values.fileSize, size <= 65_536 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    return try KeyframeAnimation.decode(file.read(upToCount: 65_537) ?? Data())
  }
}
