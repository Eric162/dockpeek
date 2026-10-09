import AppKit

// Disposable test app. It never activates itself or touches user settings.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
  let type: NSApplication.RequestUserAttentionType =
    ProcessInfo.processInfo.environment["BOUNCE_KIND"] == "informational"
    ? .informationalRequest : .criticalRequest
  let request = app.requestUserAttention(type)
  print("requested attention: \(request), pid: \(getpid())")
  fflush(stdout)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
  app.terminate(nil)
}
app.run()
