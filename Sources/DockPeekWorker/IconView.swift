import AppKit
import DockPeekCore

final class IconView: NSView {
  var image: NSImage?
  var badge = ""
  var angle = 0.0
  var squash = 1.0
  var onClick: (() -> Void)?
  var onScrollDown: (() -> Void)?
  var onRightClick: (() -> Void)?
  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 64, yBy: 64)
    transform.rotate(byRadians: angle)
    transform.scaleX(by: 1 / squash, yBy: squash)
    transform.translateX(by: -64, yBy: -64)
    transform.concat()
    let iconRect = NSRect(x: 37, y: 37, width: iconSize, height: iconSize)
    image?.draw(in: iconRect)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.white,
    ]
    let size = (badge as NSString).size(withAttributes: attributes)
    let diameter = badgeDiameter
    let width = max(diameter, size.width + 12)
    // Anchor the badge to the icon canvas. Longer labels expand toward the icon's left.
    let bubble = NSRect(
      x: iconRect.maxX - width, y: iconRect.maxY - diameter, width: width, height: diameter)
    NSColor.systemRed.setFill()
    NSBezierPath(roundedRect: bubble, xRadius: diameter / 2, yRadius: diameter / 2).fill()
    (badge as NSString).draw(
      at: NSPoint(x: bubble.midX - size.width / 2, y: bubble.midY - size.height / 2),
      withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
  }
  override func mouseDown(with event: NSEvent) { onClick?() }
  override func rightMouseDown(with event: NSEvent) { onRightClick?() }
  override func scrollWheel(with event: NSEvent) {
    if event.scrollingDeltaY < 0 { onScrollDown?() }
  }
}
