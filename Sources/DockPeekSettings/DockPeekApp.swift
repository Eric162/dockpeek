import AppKit
import DockPeekCore
import DockPeekRuntime
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct AppChoice: Identifiable {
  let id: String
  let name: String
  let icon: NSImage?
}

@MainActor
final class SettingsModel: ObservableObject {
  @Published var config = Configuration()
  @Published var message = ""
  @Published var error = false
  let root: URL
  var configURL: URL { root.appendingPathComponent("peek-config.json") }
  var apps: [AppChoice] {
    var ids = Set(config.allowedApps).union(config.applicationPaths.keys)
    // The runtime's most recent Dock snapshot includes pinned and transient tiles.
    let snapshots =
      (try? FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent(".build"),
        includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    let latest = snapshots.filter { $0.lastPathComponent.hasPrefix("peek-snapshot-") }.max {
      ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast)
        < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast)
    }
    if let latest, let snapshot = try? String(contentsOf: latest, encoding: .utf8) {
      for line in snapshot.components(separatedBy: "\n") {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("AXURL="), let url = URL(string: String(value.dropFirst(6))),
          url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier
        else { continue }
        ids.insert(id)
      }
    }
    for tile in UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps")
      as? [[String: Any]] ?? []
    {
      if let data = tile["tile-data"] as? [String: Any],
        let id = data["bundle-identifier"] as? String
      {
        ids.insert(id)
      }
    }
    return ids.map { id in
      let url =
        config.applicationPaths[id].map { URL(fileURLWithPath: $0) }
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
      let name = url?.deletingPathExtension().lastPathComponent ?? id
      return AppChoice(
        id: id, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }.sorted {
      let firstSelected = config.allowedApps.contains($0.id)
      let secondSelected = config.allowedApps.contains($1.id)
      if firstSelected != secondSelected { return firstSelected }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }
  func addApplication() {
    let panel = NSOpenPanel()
    panel.title = "Add applications"
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK else { return }
    addApplications(panel.urls)
  }
  func addApplications(_ urls: [URL]) {
    for url in urls {
      guard let id = Bundle(url: url)?.bundleIdentifier else {
        message = "Choose an application with a bundle identifier."
        error = true
        continue
      }
      config.applicationPaths[id] = url.path
      if !config.allowedApps.contains(id) { config.allowedApps.append(id) }
    }
  }
  init(
    root: URL = RuntimePaths.root()
  ) {
    self.root = root
    do {
      config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
    } catch {
      message = "Could not load settings: \(error.localizedDescription)"
      self.error = true
    }
  }
  func apply() {
    do {
      guard config.isValid else { throw NSError(domain: "DockPeek", code: 1) }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(config).write(to: configURL, options: .atomic)
      message = "Saved."
      error = false
    } catch {
      message = "Could not save: \(error.localizedDescription)"
      self.error = true
    }
  }
  func testPeek(
    bundleIdentifier: String = "local.dock-peek.settings",
    applicationPath: String = Bundle.main.bundlePath
  ) {
    do {
      let request = PeekTestRequest(
        bundleIdentifier: bundleIdentifier, applicationPath: applicationPath)
      try JSONEncoder().encode(request).write(
        to: root.appendingPathComponent("test-request.json"), options: .atomic)
      message = "Test running."
      error = false
    } catch {
      message = "Could not test: \(error.localizedDescription)"
      self.error = true
    }
  }

}

struct SettingsView: View {
  @ObservedObject var model: SettingsModel
  @ObservedObject var background: BackgroundService
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Background") {
          Toggle(
            "Start at login",
            isOn: Binding(
              get: { background.launchAtLogin },
              set: { enabled in Task { await background.setLaunchAtLogin(enabled) } }
            )
          ).disabled(background.busy)
          if background.requiresApproval {
            HStack {
              Text("Allow Dock Peek in Login Items.")
              Spacer()
              Button("Open Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
          }
          if !background.message.isEmpty && background.message != "Saved." {
            Text(background.message).font(.caption).foregroundStyle(.secondary)
          }
        }
        Section("Applications") {
          Toggle("Enable Dock Peek", isOn: $model.config.enabled)
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(model.apps) { app in
                Toggle(
                  isOn: Binding(
                    get: { model.config.allowedApps.contains(app.id) },
                    set: { enabled in
                      if enabled {
                        model.config.allowedApps.append(app.id)
                      } else {
                        model.config.allowedApps.removeAll { $0 == app.id }
                      }
                    })
                ) {
                  HStack {
                    if let icon = app.icon {
                      Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(app.name)
                  }
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxWidth: .infinity).frame(height: 150)
          Button("Add application…", systemImage: "plus") { model.addApplication() }
        }
        Section("Appearance") {
          HStack {
            Text("Visible portion")
            Slider(value: $model.config.peekFraction, in: 0.1...1)
            Text("\(Int(model.config.peekFraction * 100))%").monospacedDigit().frame(width: 40)
          }
          VStack(alignment: .leading, spacing: 10) {
            Picker("Entry", selection: $model.config.entryAnimation) {
              Text("Slide up").tag(EntryAnimation.slide)
              Text("Tumble").tag(EntryAnimation.tumble)
              Text("None").tag(EntryAnimation.none)
            }
            if model.config.entryAnimation == .tumble {
              durationRow("Duration", value: $model.config.tumbleDuration, range: 0.5...3)
                .padding(.leading, 20)
            } else if model.config.entryAnimation == .slide {
              durationRow("Duration", value: $model.config.slideDuration, range: 0.1...1)
                .padding(.leading, 20)
            }
          }
          VStack(alignment: .leading, spacing: 10) {
            Picker("Dismissal", selection: $model.config.dismissAnimation) {
              Text("Slide down").tag(DismissAnimation.slide)
              Text("None").tag(DismissAnimation.none)
            }
            if model.config.dismissAnimation == .slide {
              durationRow("Duration", value: $model.config.dismissDuration, range: 0.1...1)
                .padding(.leading, 20)
            }
          }
        }
        Section("Interactions") {
          Toggle("Click to open the app", isOn: $model.config.openAppOnClick)
          Toggle("Scroll down to dismiss", isOn: $model.config.scrollDismisses)
          Toggle("Right-click to dismiss", isOn: $model.config.rightClickDismisses)
        }
      }.formStyle(.grouped)
      HStack {
        Text(model.message).font(.caption).foregroundStyle(model.error ? .red : .secondary)
        Spacer()
        Button("Test Dock Peek") {
          background.prepare()
          model.testPeek()
        }.disabled(background.requiresApproval)
        Button("Apply") { model.apply() }.keyboardShortcut(.defaultAction)
      }.padding()
    }.frame(minWidth: 470, minHeight: 840)
      .task {
        await background.migrateLegacyAgent()
        if CommandLine.arguments.contains("--unregister-background") {
          await background.setLaunchAtLogin(false)
        } else if CommandLine.arguments.contains("--register-background") {
          await background.setLaunchAtLogin(true)
        } else {
          background.prepare()
        }
        if CommandLine.arguments.contains("--test-self") { model.testPeek() }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { background.refresh() }
      }
  }
  func durationRow(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View
  {
    HStack {
      Text(name)
      Slider(value: value, in: range)
      Text(String(format: "%.2f s", value.wrappedValue)).monospacedDigit().frame(width: 54)
    }
  }
}

@MainActor
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if RuntimePaths.isVerification(RuntimePaths.root()),
      let index = CommandLine.arguments.firstIndex(of: "--verify-quit-after"),
      CommandLine.arguments.indices.contains(index + 1),
      let seconds = Double(CommandLine.arguments[index + 1]), seconds > 0
    {
      DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }
    let event = NSAppleEventManager.shared().currentAppleEvent
    let login =
      event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
      .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true
    if login || CommandLine.arguments.contains("--login-start") {
      let background = BackgroundService(
        root: RuntimePaths.root())
      background.prepare()
      if background.message.isEmpty {
        for window in NSApp.windows { window.orderOut(nil) }
        NSApp.terminate(nil)
      }
    }
  }
}

@main
struct DockPeekSettingsApp: App {
  @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) private var delegate
  @StateObject private var model = SettingsModel()
  @StateObject private var background = BackgroundService(
    root: RuntimePaths.root())
  var body: some Scene {
    WindowGroup("Dock Peek") { SettingsView(model: model, background: background) }
      .defaultSize(width: 500, height: 860)
  }
}
