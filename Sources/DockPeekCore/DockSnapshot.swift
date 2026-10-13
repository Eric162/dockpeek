import CoreGraphics
import Foundation

public struct Tile: Sendable {
  public init(bundle: String, name: String, url: URL, badge: String?, rect: CGRect) {
    self.bundle = bundle
    self.name = name
    self.url = url
    self.badge = badge
    self.rect = rect
  }
  public let bundle: String
  public let name: String
  public let url: URL
  public let badge: String?
  public let rect: CGRect
}

@Sendable public func tiles(_ snapshot: String) -> [Tile] {
  snapshot.components(separatedBy: "    ELEMENT\n").compactMap { section -> Tile? in
    guard let name = section.firstMatch(of: #/AXTitle=([^\n]+)/#)?.1,
      let path = section.firstMatch(of: #/AXURL=([^\n]+)/#)?.1,
      let url = URL(string: String(path)), let bundle = Bundle(url: url)?.bundleIdentifier,
      let frame = section.firstMatch(
        of: #/AXFrame=.*value = x:([0-9.-]+) y:([0-9.-]+) w:([0-9.-]+) h:([0-9.-]+)/#),
      let x = Double(frame.1), let y = Double(frame.2), let width = Double(frame.3),
      let height = Double(frame.4), [x, y, width, height].allSatisfy(\.isFinite)
    else { return nil }
    return Tile(
      bundle: bundle, name: String(name), url: url,
      badge: section.firstMatch(of: #/AXStatusLabel=([^\n]+)/#).map { String($0.1) },
      rect: CGRect(x: x, y: y, width: width, height: height))
  }
}
