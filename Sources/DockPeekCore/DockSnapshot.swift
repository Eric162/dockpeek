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
@Sendable func match(_ pattern: String, _ text: String) -> [String]? {
  guard let regex = try? NSRegularExpression(pattern: pattern),
    let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
  else {
    return nil
  }
  var captures: [String] = []
  for index in 1..<found.numberOfRanges {
    guard let range = Range(found.range(at: index), in: text) else { return nil }
    captures.append(String(text[range]))
  }
  return captures
}
@Sendable public func tiles(_ snapshot: String) -> [Tile] {
  snapshot.components(separatedBy: "    ELEMENT\n").compactMap { section -> Tile? in
    guard let name = match("AXTitle=([^\\n]+)", section)?.first,
      let path = match("AXURL=([^\\n]+)", section)?.first,
      let url = URL(string: path), let bundle = Bundle(url: url)?.bundleIdentifier,
      let coordinates = match(
        "AXFrame=.*value = x:([0-9.-]+) y:([0-9.-]+) w:([0-9.-]+) h:([0-9.-]+)", section)
    else { return nil }
    let numbers = coordinates.compactMap { Double($0) }
    guard numbers.count == 4, numbers.allSatisfy(\.isFinite) else { return nil }
    return Tile(
      bundle: bundle, name: name, url: url,
      badge: match("AXStatusLabel=([^\\n]+)", section)?.first,
      rect: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
  }
}
