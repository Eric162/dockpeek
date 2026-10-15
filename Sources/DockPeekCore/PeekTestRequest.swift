import Foundation

public struct PeekTestRequest: Codable, Sendable {
  public static let notificationName = Notification.Name("local.dock-peek.test-request")
  public let bundleIdentifier: String
  public let applicationPath: String
  public let expiresAt: Date
  public let token: String
  public let configuration: Configuration?

  public init(
    bundleIdentifier: String, applicationPath: String, configuration: Configuration? = nil,
    now: Date = Date()
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.applicationPath = applicationPath
    self.configuration = configuration
    expiresAt = now.addingTimeInterval(10)
    token = UUID().uuidString
  }
  public var isActive: Bool { isActive(at: Date()) }
  public func isActive(at now: Date) -> Bool { expiresAt > now }
}
