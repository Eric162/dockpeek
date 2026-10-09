import AppKit

// Disposable fixture for overlay lifecycle tests. Never requests native bouncing.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
for (seconds, badge) in [(2.0, "3"), (6.0, "8"), (10.0, "")] {
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    app.dockTile.badgeLabel = badge.isEmpty ? nil : badge
    print("FIXTURE badge=\(badge.isEmpty ? "none" : badge)")
    fflush(stdout)
  }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { app.terminate(nil) }
app.run()
