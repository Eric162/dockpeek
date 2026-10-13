import AppKit
import DockPeekCore

@MainActor
final class Presentation {
  let panel: NSPanel
  let view = IconView(frame: NSRect(x: 0, y: 0, width: panelSize, height: panelSize))
  var motion = PresentationMotion()
  var badge = ""
  private var imagePath = ""
  private(set) var iconLoads = 0

  init(name: String) {
    panel = NSPanel(
      contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isReleasedWhenClosed = false
    panel.title = "Dock Peek: \(name)"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = view
  }
  func updateIcon(path: String) {
    guard imagePath != path else { return }
    imagePath = path
    view.image = NSWorkspace.shared.icon(forFile: path)
    iconLoads += 1
  }
  func show(
    at point: CGPoint, screen: CGRect, animation: AnimationIdentifier, configuration: Configuration,
    registry: AnimationRegistry
  ) {
    motion.show(
      at: point, screen: screen, animation: animation, now: ProcessInfo.processInfo.systemUptime,
      configuration: configuration, registry: registry, badge: badge)
    log("ENTER \(panel.title) style=\(animation.rawValue)")
    animate(now: ProcessInfo.processInfo.systemUptime)
    panel.orderFrontRegardless()
  }
  func hide(configuration: Configuration, registry: AnimationRegistry) {
    let previous = motion.phase
    motion.hide(
      animation: configuration.dismissAnimation, now: ProcessInfo.processInfo.systemUptime,
      configuration: configuration, registry: registry, badge: badge)
    if motion.phase != previous {
      log("EXIT \(panel.title) style=\(configuration.dismissAnimation.rawValue)")
    }
  }
  func animate(now: Double) {
    let previous = motion.phase
    guard let pose = motion.step(now: now) else {
      if previous != .hidden {
        panel.orderOut(nil)
        log("HIDDEN \(panel.title)")
      }
      return
    }
    panel.setFrameOrigin(pose.point)
    view.angle = pose.angle
    view.squash = pose.squash
    panel.alphaValue = pose.opacity
    view.needsDisplay = true
    if previous == .entering, motion.phase == .shown { log("SETTLED \(panel.title)") }
  }
}
