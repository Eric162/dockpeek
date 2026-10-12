import AppKit
import DockPeekCore
import SwiftUI

extension SettingsModel {
  func installAnimation() {
    let panel = NSOpenPanel()
    panel.title = "Install animation plugin"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      animations.reload()
      let plugin = try animations.install(url)
      if plugin.descriptor.stages.contains(.entry) {
        config.entryAnimation = AnimationIdentifier(rawValue: plugin.descriptor.id)
      } else {
        config.dismissAnimation = AnimationIdentifier(rawValue: plugin.descriptor.id)
      }
      animationRevision += 1
      message = "Installed \(plugin.descriptor.name). Apply to use it."
      error = false
    } catch {
      message = "Could not install animation: \(error.localizedDescription)"
      self.error = true
    }
  }
}

struct AnimationSettingsView: View {
  @ObservedObject var model: SettingsModel
  let stage: AnimationStage
  private var selection: Binding<AnimationIdentifier> {
    Binding(
      get: { stage == .entry ? model.config.entryAnimation : model.config.dismissAnimation },
      set: { value in
        if stage == .entry {
          model.config.entryAnimation = value
        } else {
          model.config.dismissAnimation = value
        }
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(stage == .entry ? "Entry" : "Dismissal", selection: selection) {
        Text("None").tag(AnimationIdentifier.none)
        ForEach(
          model.animations.registry.plugins.map(\.descriptor).filter { $0.stages.contains(stage) }
        ) { plugin in
          Text(plugin.name).tag(AnimationIdentifier(rawValue: plugin.id))
        }
      }
      if let plugin = model.animations.registry.plugin(
        id: selection.wrappedValue.rawValue, stage: stage)
      {
        ForEach(plugin.descriptor.settings) { setting in
          control(setting, plugin: plugin.descriptor).padding(.leading, 20)
        }
      } else if selection.wrappedValue != .none {
        Text("Selected animation is unavailable. Install it or choose another.")
          .font(.caption).foregroundStyle(.red)
      }
    }
  }
  private func binding(_ setting: AnimationSetting, plugin: AnimationDescriptor) -> Binding<
    AnimationValue
  > {
    Binding(
      get: {
        plugin.resolved(model.config.settings(for: plugin.id, stage: stage))[setting.id]
          ?? setting.defaultValue
      },
      set: { value in
        if stage == .entry {
          model.config.entrySettings[plugin.id, default: [:]][setting.id] = value
        } else {
          model.config.dismissalSettings[plugin.id, default: [:]][setting.id] = value
        }
      })
  }
  @ViewBuilder
  private func control(_ setting: AnimationSetting, plugin: AnimationDescriptor) -> some View {
    let value = binding(setting, plugin: plugin)
    switch setting.kind {
    case .number:
      if let minimum = setting.minimum, let maximum = setting.maximum {
        HStack {
          Text(setting.name)
          Slider(
            value: Binding(
              get: { value.wrappedValue.number ?? minimum },
              set: { value.wrappedValue = .number($0) }), in: minimum...maximum)
          Text(String(format: "%.2f", value.wrappedValue.number ?? minimum)).monospacedDigit()
            .frame(width: 54)
        }
      }
    case .toggle:
      Toggle(
        setting.name,
        isOn: Binding(
          get: { value.wrappedValue == .toggle(true) },
          set: { value.wrappedValue = .toggle($0) }))
    case .choice:
      Picker(setting.name, selection: value) {
        ForEach(setting.choices ?? [], id: \.self) { choice in
          Text(choice).tag(AnimationValue.choice(choice))
        }
      }
    }
  }
}
