import Foundation

public struct PeekTestRequest: Codable {
  public let bundleIdentifier: String
  public let applicationPath: String
  public let expiresAt: Date
  public let token: String

  public init(bundleIdentifier: String, applicationPath: String, now: Date = Date()) {
    self.bundleIdentifier = bundleIdentifier
    self.applicationPath = applicationPath
    expiresAt = now.addingTimeInterval(10)
    token = UUID().uuidString
  }
  public var isActive: Bool { expiresAt > Date() }
}
