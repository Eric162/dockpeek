import AppKit
import DockPeekCore
import DockPeekRuntime

@MainActor
final class WorkerController {
  let root: URL
  private let configURL: URL
  private let demo: Bool
  private let override: Set<String>?
  private let reader = SnapshotReader()
  private var state = WorkerState()
  private var config = Configuration()
  private var presentations: [String: Presentation] = [:]
  private var updateTask: Task<Void, Never>?
  private var refresh: Timer?
  private var animation: Timer?
  private var failureLogged = false
  private var commandToken = ""
  private var stopping = false
  private var animationTicks = 0
  private var probeReads = 0

  init(root: URL, configURL: URL, demo: Bool = false, allowedOverride: Set<String>? = nil) {
    self.root = root
    self.configURL = configURL
    self.demo = demo
    override = allowedOverride
  }
  func start() {
    tick()
    refresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }

  }
  func stop() async {
    stopping = true
    refresh?.invalidate()
    animation?.invalidate()
    updateTask?.cancel()
    await updateTask?.value
    updateTask = nil
    for presentation in presentations.values { presentation.panel.orderOut(nil) }
    writeDiagnostics()
    log("STOPPED worker; probe drained")
  }
  private func tick() {
    guard !stopping else { return }
    do {
      let next = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
      guard next.isValid else { throw CocoaError(.fileReadCorruptFile) }
      config = next
      if let override { config.allowedApps = Array(override) }
    } catch {
      hideAll()
      updateTask?.cancel()
      return
    }
    let test = testRequest()
    guard config.enabled || test != nil else {
      hideAll()
      updateTask?.cancel()
      return
    }
    guard updateTask == nil else { return }
    updateTask = Task { [weak self] in
      guard let self else { return }
      defer { updateTask = nil }
      do {
        let probe = root.appendingPathComponent(
          ".build/Dock Tile Probe.app/Contents/MacOS/DockTileProbe")
        let snapshot = try await reader.read(root: root, probe: probe)
        try Task.checkCancellation()
        guard !stopping else { return }
        failureLogged = false
        probeReads += 1
        apply(snapshot: snapshot, test: testRequest())
      } catch {
        hideAll()
        if !(error is CancellationError), !failureLogged {
          log("PROBE-FAILED \(error)")
          failureLogged = true
        }
      }
      writeDiagnostics()
    }
  }
  private func testRequest() -> PeekTestRequest? {
    (try? Data(contentsOf: root.appendingPathComponent("test-request.json")))
      .flatMap { try? JSONDecoder().decode(PeekTestRequest.self, from: $0) }
      .flatMap { $0.isActive ? $0 : nil }
  }
  private func hideAll() {
    _ = state.update(configuration: nil, observations: nil)
    for presentation in presentations.values { presentation.hide(configuration: config) }
    ensureAnimationTimer()
    writeDiagnostics()
  }
  private func apply(snapshot: String, test: PeekTestRequest?) {
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    var dockTiles = tiles(snapshot)
    if let test, !dockTiles.contains(where: { $0.bundle == test.bundleIdentifier }),
      let screen = NSScreen.screens.first
    {
      dockTiles.append(
        Tile(
          bundle: test.bundleIdentifier, name: "Dock Peek",
          url: URL(fileURLWithPath: test.applicationPath),
          badge: nil,
          rect: CGRect(
            x: screen.frame.midX - 32, y: primaryHeight - screen.frame.minY, width: 64, height: 80))
      )
    }
    let command = verificationCommand()
    let placements = dockTiles.compactMap {
      placement($0, primaryHeight: primaryHeight, command: command)
    }
    let observations = placements.map {
      BadgeObservation(
        bundle: $0.tile.bundle, badge: demo ? "3" : $0.tile.badge ?? "", dockVisible: $0.dockVisible
      )
    }
    let desired = state.update(configuration: config, observations: observations, test: test)
    for placement in placements {
      if let badge = desired[placement.tile.bundle] { present(placement, badge: badge) }
    }
    for (bundle, presentation) in presentations where desired[bundle] == nil {
      presentation.hide(configuration: config)
    }
    handle(command: command)
    ensureAnimationTimer()
  }
  private struct Placement {
    let tile: Tile
    let screen: NSScreen
    let dockVisible: Bool
  }
  private func placement(_ tile: Tile, primaryHeight: Double, command: VerificationCommand?)
    -> Placement?
  {
    let center = CGPoint(x: tile.rect.midX, y: primaryHeight - tile.rect.midY)
    guard
      let screen = NSScreen.screens.min(by: {
        hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
          < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
      })
    else { return nil }
    let screenAX = CGRect(
      x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
      width: screen.frame.width, height: screen.frame.height)
    let dockVisible: Bool
    switch command?.dockVisibility {
    case .visible: dockVisible = true
    case .hidden: dockVisible = false
    default: dockVisible = screenAX.intersects(tile.rect.insetBy(dx: 2, dy: 2))
    }
    return Placement(tile: tile, screen: screen, dockVisible: dockVisible)
  }
  private func present(_ placement: Placement, badge: VisibleBadge) {
    let tile = placement.tile
    let presentation = presentations[tile.bundle] ?? Presentation(name: tile.name)
    presentation.updateIcon(path: tile.url.path)
    if presentation.view.badge != badge.badge {
      presentation.view.badge = badge.badge
      presentation.view.needsDisplay = true
    }
    if presentation.badge != badge.badge { log("BADGE \(tile.bundle)=\(badge.badge)") }
    presentation.badge = badge.badge
    let dismiss = { [weak self, weak presentation] in
      guard let self, let presentation else { return }
      state.dismiss(tile.bundle)
      presentation.hide(configuration: config)
      ensureAnimationTimer()
    }
    presentation.view.onClick = { [weak self] in
      guard let self, config.openAppOnClick else { return }
      dismiss()
      let options = NSWorkspace.OpenConfiguration()
      options.activates = true
      NSWorkspace.shared.openApplication(at: tile.url, configuration: options) { _, error in
        if let error { log("OPEN-FAILED \(error.localizedDescription)") }
      }
    }
    presentation.view.onScrollDown = { [weak self] in
      guard self?.config.scrollDismisses == true else { return }
      log("SCROLL-DISMISS \(tile.bundle)")
      dismiss()
    }
    presentation.view.onRightClick = { [weak self] in
      guard self?.config.rightClickDismisses == true else { return }
      log("RIGHT-CLICK-DISMISS \(tile.bundle)")
      dismiss()
    }
    let screen = placement.screen.frame
    let point = CGPoint(
      x: min(max(tile.rect.midX - 64, screen.minX), screen.maxX - panelSize),
      y: restingY(edge: screen.minY, fraction: config.peekFraction))
    if presentation.motion.phase == .hidden || presentation.motion.phase == .exiting {
      presentation.show(at: point, screen: screen, animation: badge.entry)
    } else if presentation.motion.target != point {
      presentation.motion.target = point
      if presentation.motion.phase == .shown {
        presentation.animate(now: ProcessInfo.processInfo.systemUptime, configuration: config)
      }
    }
    presentations[tile.bundle] = presentation
  }
  private func ensureAnimationTimer() {
    guard presentations.values.contains(where: { $0.motion.isAnimating }) else {
      animation?.invalidate()
      animation = nil
      pruneHidden()
      return
    }
    guard animation == nil else { return }
    animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.animate() }
    }
    animation?.tolerance = 0.002
  }
  private func animate() {
    animationTicks += 1
    let now = ProcessInfo.processInfo.systemUptime
    for presentation in presentations.values where presentation.motion.isAnimating {
      presentation.animate(now: now, configuration: config)
    }
    pruneHidden()
    ensureAnimationTimer()
  }
  private func pruneHidden() {
    let hidden = presentations.filter {
      $0.value.motion.phase == .hidden && state.visible[$0.key] == nil
    }
    for (bundle, presentation) in hidden {
      presentation.panel.close()
      presentations.removeValue(forKey: bundle)
    }
  }
  private enum DockVisibility: String, Decodable { case visible, hidden }
  private struct VerificationCommand: Decodable {
    let token: String
    let dockVisibility: DockVisibility?
    let dismiss: String?
  }
  private func verificationCommand() -> VerificationCommand? {
    guard RuntimePaths.isVerification(root) else { return nil }
    return (try? Data(contentsOf: root.appendingPathComponent("command.json")))
      .flatMap { try? JSONDecoder().decode(VerificationCommand.self, from: $0) }
  }
  private func handle(command: VerificationCommand?) {
    guard let command, command.token != commandToken else { return }
    commandToken = command.token
    for presentation in presentations.values where presentation.motion.phase == .shown {
      if command.dismiss == "rightClick",
        let event = NSEvent.mouseEvent(
          with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: presentation.panel.windowNumber, context: nil, eventNumber: 1,
          clickCount: 1, pressure: 1)
      {
        presentation.view.rightMouseDown(with: event)
      }
      if command.dismiss == "scroll",
        let cg = CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -12, wheel2: 0,
          wheel3: 0),
        let event = NSEvent(cgEvent: cg)
      {
        presentation.view.scrollWheel(with: event)
      }
    }
  }
  private func writeDiagnostics() {
    guard RuntimePaths.isVerification(root) else { return }
    let report = [
      "animationTicks": animationTicks, "probeReads": probeReads,
      "presentations": presentations.count, "visible": state.visible.count,
      "animationTimerActive": animation == nil ? 0 : 1,
      "iconLoads": presentations.values.reduce(0) { $0 + $1.iconLoads },
    ]
    if let data = try? JSONEncoder().encode(report) {
      try? data.write(to: root.appendingPathComponent("diagnostics.json"), options: .atomic)
    }
  }
}
