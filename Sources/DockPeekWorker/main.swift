import AppKit
import Darwin
import DockPeekCore

// The worker runs independently of the settings application.
let args = Array(CommandLine.arguments.dropFirst())
let installed =
  args.contains("--installed") || Bundle.main.bundleIdentifier == "local.dock-peek.worker"
let root =
  installed
  ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Dock Peek")
  : URL(fileURLWithPath: args.first ?? FileManager.default.currentDirectoryPath)
let allowedOverride: Set<String>? =
  installed || (args.count > 1 && args[1] == "-")
  ? nil
  : Set(
    (args.count > 1 ? args[1] : "com.openai.codex").split(separator: ",").map(String.init))
let duration = installed ? 0 : (args.count > 2 ? Double(args[2]) ?? 45 : 45)
let demo = args.contains("--demo")
let configPath =
  args.firstIndex(of: "--config").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
  ?? root.appendingPathComponent("peek-config.json").path
var config = Configuration()
if FileManager.default.fileExists(atPath: configPath) {
  do {
    config = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
  } catch {
    fputs("Cannot read configuration: \(error)\n", stderr)
    exit(1)
  }
}
guard config.peekFraction > 0, config.peekFraction <= 1,
  ["slide", "tumble", "none"].contains(config.entryAnimation),
  ["slide", "none"].contains(config.dismissAnimation),
  [config.slideDuration, config.dismissDuration, config.tumbleDuration].allSatisfy({
    $0.isFinite && $0 > 0
  })
else {
  fputs("Invalid animation configuration.\n", stderr)
  exit(1)
}
@Sendable func log(_ text: String) {
  print(text)
  fflush(stdout)
}
// A lock prevents a session worker and a registered login worker from overlapping.
var workerLock: Int32 = -1
if installed {
  do {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
  } catch {
    fputs("Cannot create worker directory: \(error)\n", stderr)
    exit(1)
  }
  workerLock = open(
    root.appendingPathComponent("worker.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
  guard workerLock >= 0, flock(workerLock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
  freopen(root.appendingPathComponent("overlay.log").path, "a", stdout)
  freopen(root.appendingPathComponent("overlay-error.log").path, "a", stderr)
  do {
    try String(getpid()).write(
      to: root.appendingPathComponent("worker.pid"), atomically: true, encoding: .utf8)
  } catch {
    fputs("Cannot write worker PID: \(error)\n", stderr)
    exit(1)
  }
}
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
    image?.draw(in: NSRect(x: 37, y: 37, width: iconSize, height: iconSize))
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white,
    ]
    let size = (badge as NSString).size(withAttributes: attributes)
    let bubble = NSRect(
      x: 110 - max(23, size.width + 12), y: 79, width: max(23, size.width + 12), height: 23)
    NSColor.systemRed.setFill()
    NSBezierPath(roundedRect: bubble, xRadius: 11.5, yRadius: 11.5).fill()
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
@MainActor
final class Presentation {
  let panel: NSPanel
  let view = IconView(frame: NSRect(x: 0, y: 0, width: panelSize, height: panelSize))
  var target: CGPoint = .zero
  var start: CGPoint = .zero
  var screen: CGRect = .zero
  var began = 0.0
  var phase = "hidden"
  var fromLeft = true
  var entryAnimation = "slide"
  var badge = ""
  init(name: String) {
    panel = NSPanel(
      contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.title = "Dock Peek: \(name)"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = view
  }
  func show(at point: CGPoint, screen: CGRect, animation: String) {
    entryAnimation = animation
    target = point
    self.screen = screen
    fromLeft = point.x + 64 - screen.minX <= screen.maxX - point.x - 64
    phase = "entering"
    began = ProcessInfo.processInfo.systemUptime
    start =
      entryAnimation == "tumble"
      ? CGPoint(x: fromLeft ? screen.minX - panelSize : screen.maxX, y: screen.minY - 37)
      : CGPoint(x: point.x, y: screen.minY - panelSize - 4)
    if entryAnimation == "none" { start = point }
    panel.setFrameOrigin(start)
    panel.orderFrontRegardless()
    log(
      "ENTER \(panel.title) style=\(entryAnimation) side=\(fromLeft ? "left" : "right") fraction=\(config.peekFraction)"
    )
  }
  func hide() {
    guard phase != "hidden", phase != "exiting" else { return }
    phase = "exiting"
    began = ProcessInfo.processInfo.systemUptime
    start = panel.frame.origin
    log("EXIT \(panel.title) style=\(config.dismissAnimation)")
  }
  func animate(now: Double) {
    guard phase != "hidden" else { return }
    if phase == "shown" {
      if abs(panel.frame.minX - target.x) > 1 || abs(panel.frame.minY - target.y) > 1 {
        panel.setFrameOrigin(target)
      }
      return
    }
    var pose = Pose(point: target)
    if phase == "entering" {
      let length = entryAnimation == "tumble" ? config.tumbleDuration : config.slideDuration
      let t = min((now - began) / length, 1)
      if entryAnimation == "tumble" {
        pose = tumblePose(progress: t, start: start, target: target, fromLeft: fromLeft)
      } else if entryAnimation == "slide" {
        pose.point.y = start.y + (target.y - start.y) * ease(t)
      }
      if t >= 1 || entryAnimation == "none" {
        phase = "shown"
        pose = Pose(point: target)
        log("SETTLED \(panel.title) frame=\(CGRect(origin: target, size: panel.frame.size))")
      }
    } else if phase == "exiting" {
      let t = min((now - began) / config.dismissDuration, 1)
      let bottom = screen.minY - panelSize - 4
      pose.point = CGPoint(x: start.x, y: start.y + (bottom - start.y) * ease(t))
      if t >= 1 || config.dismissAnimation == "none" {
        panel.orderOut(nil)
        phase = "hidden"
        log("HIDDEN \(panel.title)")
        return
      }
    }
    panel.setFrameOrigin(pose.point)
    view.angle = pose.angle
    view.squash = pose.squash
    view.needsDisplay = true
  }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var presentations: [String: Presentation] = [:]
var dismissed: [String: String] = [:]
var dockCovered: [String: String] = [:]
var simulatedDockVisible = false
@MainActor
enum Worker {
  static func update() {
    do {
      let next = try JSONDecoder().decode(
        Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
      guard next.isValid else { throw NSError(domain: "DockPeek", code: 1) }
      config = next
    } catch {
      for presentation in presentations.values { presentation.hide() }
      return
    }
    let request = (try? Data(contentsOf: root.appendingPathComponent("test-request.json")))
      .flatMap { try? JSONDecoder().decode(PeekTestRequest.self, from: $0) }
    let test = request.flatMap { $0.isActive ? $0 : nil }
    guard config.enabled || test != nil else {
      for presentation in presentations.values { presentation.hide() }
      return
    }
    var allowed = config.enabled ? (allowedOverride ?? Set(config.allowedApps)) : []
    if let test { allowed.insert(test.bundleIdentifier) }
    guard let snapshot = readSnapshot() else { return }
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    var visible: Set<String> = []
    var dockTiles = tiles(snapshot)
    if let test, !dockTiles.contains(where: { $0.bundle == test.bundleIdentifier }),
      let screen = NSScreen.screens.first
    {
      dockTiles.append(
        Tile(
          bundle: test.bundleIdentifier, name: "Dock Peek",
          url: URL(fileURLWithPath: test.applicationPath), badge: nil,
          rect: CGRect(
            x: screen.frame.midX - 32, y: primaryHeight - screen.frame.minY, width: 64, height: 80))
      )
    }
    for tile in dockTiles where allowed.contains(tile.bundle) {
      if update(tile, test: test, primaryHeight: primaryHeight) {
        visible.insert(tile.bundle)
      }
    }
    for (bundle, presentation) in presentations where !visible.contains(bundle) {
      presentation.hide()
    }
  }

  private static func readSnapshot() -> String? {
    let snapshotURL = root.appendingPathComponent(".build/peek-snapshot-\(getpid()).txt")
    do {
      try Data().write(to: snapshotURL)
    } catch {
      log("Cannot initialize probe snapshot: \(error)")
      return nil
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [
      "-W", "-g", "-n", "--stdout", snapshotURL.path,
      "--stderr", root.appendingPathComponent(".build/peek-probe-error.txt").path,
      root.appendingPathComponent(".build/Dock Tile Probe.app").path,
    ]
    do {
      try process.run()
    } catch {
      log("Cannot launch Dock probe: \(error)")
      return nil
    }
    process.waitUntilExit()
    guard let snapshot = try? String(contentsOf: snapshotURL, encoding: .utf8), !snapshot.isEmpty
    else { return nil }
    return snapshot
  }

  private static func update(_ tile: Tile, test: PeekTestRequest?, primaryHeight: Double) -> Bool {
    let testing = test?.bundleIdentifier == tile.bundle
    let badge = testing ? "3" : (demo ? "3" : tile.badge ?? "")
    let badgeKey: String
    if let test, testing {
      badgeKey = "test-\(test.token)"
    } else {
      badgeKey = badge
    }
    if badge.isEmpty {
      dismissed.removeValue(forKey: tile.bundle)
      dockCovered.removeValue(forKey: tile.bundle)
      return false
    }
    if let previous = dismissed[tile.bundle], previous != badgeKey {
      dismissed.removeValue(forKey: tile.bundle)
    }
    if dismissed[tile.bundle] == badgeKey { return false }
    let center = NSPoint(x: tile.rect.midX, y: primaryHeight - tile.rect.midY)
    guard
      let screen = NSScreen.screens.min(by: {
        hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
          < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
      })
    else { return false }
    let screenAX = CGRect(
      x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width,
      height: screen.frame.height)
    guard !simulatedDockVisible, !screenAX.intersects(tile.rect.insetBy(dx: 2, dy: 2)) else {
      dockCovered[tile.bundle] = badge
      return false
    }
    present(tile, badge: badge, badgeKey: badgeKey, screen: screen)
    return true
  }

  private static func present(_ tile: Tile, badge: String, badgeKey: String, screen: NSScreen) {
    let presentation = presentations[tile.bundle] ?? Presentation(name: tile.name)
    presentation.view.image = NSWorkspace.shared.icon(forFile: tile.url.path)
    presentation.view.badge = badge
    presentation.view.needsDisplay = true
    if presentation.badge != badge { log("BADGE \(tile.bundle)=\(badge)") }
    presentation.badge = badge
    let dismiss: () -> Void = { [weak presentation] in
      guard let presentation else { return }
      dismissed[tile.bundle] = badgeKey
      presentation.hide()
    }
    presentation.view.onClick = {
      guard config.openAppOnClick else { return }
      log("OPEN \(tile.bundle)")
      dismiss()
      let options = NSWorkspace.OpenConfiguration()
      options.activates = true
      NSWorkspace.shared.openApplication(at: tile.url, configuration: options) { app, error in
        if let error {
          log("OPEN-FAILED \(tile.bundle): \(error.localizedDescription)")
        } else {
          log("OPENED \(app?.bundleIdentifier ?? tile.bundle)")
        }
      }
    }
    presentation.view.onScrollDown = {
      guard config.scrollDismisses else { return }
      log("SCROLL-DISMISS \(tile.bundle)")
      dismiss()
    }
    presentation.view.onRightClick = {
      guard config.rightClickDismisses else { return }
      log("RIGHT-CLICK-DISMISS \(tile.bundle)")
      dismiss()
    }
    let x = min(max(tile.rect.midX - 64, screen.frame.minX), screen.frame.maxX - panelSize)
    let target = CGPoint(
      x: x, y: restingY(edge: screen.frame.minY, fraction: config.peekFraction))
    if presentation.phase == "hidden" || presentation.phase == "exiting" {
      let animation = entryStyle(
        badge: badge, coveredBadge: dockCovered[tile.bundle], configured: config.entryAnimation)
      presentation.show(at: target, screen: screen.frame, animation: animation)
      dockCovered.removeValue(forKey: tile.bundle)
    } else {
      presentation.target = target
    }
    presentations[tile.bundle] = presentation
  }

}
log(
  "Dock Peek; config=\(configPath); demo=\(demo); duration=\(duration == 0 ? "indefinite" : String(duration))"
)
MainActor.assumeIsolated { Worker.update() }
let refresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
  MainActor.assumeIsolated { Worker.update() }
}
let animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
  MainActor.assumeIsolated {
    let now = ProcessInfo.processInfo.systemUptime
    for presentation in presentations.values { presentation.animate(now: now) }
  }
}
if args.contains("--test-click") || args.contains("--test-right-click")
  || args.contains("--test-scroll")
{
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    for presentation in presentations.values where presentation.phase == "shown" {
      let point = NSPoint(x: 64, y: iconTop - iconSize * config.peekFraction / 2)
      if args.contains("--test-scroll") {
        if let cgEvent = CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -12, wheel2: 0,
          wheel3: 0),
          let event = NSEvent(cgEvent: cgEvent)
        {
          presentation.view.scrollWheel(with: event)
        }
        continue
      }
      if let event = NSEvent.mouseEvent(
        with: args.contains("--test-right-click") ? .rightMouseDown : .leftMouseDown,
        location: point,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: presentation.panel.windowNumber, context: nil, eventNumber: 1,
        clickCount: 1, pressure: 1)
      {
        presentation.panel.sendEvent(event)
      }
    }
  }
}
if args.contains("--test-dock-return") {
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    simulatedDockVisible = true
    Worker.update()
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    simulatedDockVisible = false
    Worker.update()
  }
}
if duration > 0 {
  DispatchQueue.main.asyncAfter(deadline: .now() + duration) { app.terminate(nil) }
}
app.run()
