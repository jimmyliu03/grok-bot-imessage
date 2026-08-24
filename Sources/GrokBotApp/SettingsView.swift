import GrokBotCore
import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    TabView {
      Form {
        TextField("Model", text: $model.configuration.model)
        Toggle("Launch Grok Bot at login", isOn: $model.configuration.launchAtLogin)
        Toggle("Expose Messages tools to owners", isOn: $model.configuration.messageToolsEnabled)
        Toggle("Expose Reminders tools to owners", isOn: $model.configuration.remindersEnabled)
        HStack {
          Button("Run Setup Again") { model.showOnboarding() }
          Spacer()
          Button("Save") { model.saveConfiguration() }.buttonStyle(.borderedProminent)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("General", systemImage: "gear") }

      Form {
        Picker("Write approvals", selection: $model.configuration.toolApprovalMode) {
          Text("Always ask in iMessage").tag(ToolApprovalMode.alwaysAsk)
          Text("Trust owners automatically").tag(ToolApprovalMode.trustedOwners)
        }
        Text(
          "Always ask is strongly recommended. Reading Messages and Reminders is owner-only but does not prompt for every lookup."
        )
        .font(.caption).foregroundStyle(.secondary)
        Stepper(
          "Session context: \(model.configuration.maxSessionMessages) messages",
          value: $model.configuration.maxSessionMessages, in: 4...80, step: 4)
        HStack {
          Spacer()
          Button("Save") { model.saveConfiguration() }.buttonStyle(.borderedProminent)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("Safety", systemImage: "lock.shield") }

      VStack(alignment: .leading, spacing: 10) {
        Text("System prompt").font(.headline)
        TextEditor(text: $model.configuration.systemPrompt)
          .font(.body.monospaced())
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        HStack {
          Button("Restore Default") {
            model.configuration.systemPrompt = BotConfiguration.defaultSystemPrompt
          }
          Spacer()
          Button("Save") { model.saveConfiguration() }.buttonStyle(.borderedProminent)
        }
      }
      .padding()
      .tabItem { Label("Agent", systemImage: "text.bubble") }
    }
    .frame(width: 560, height: 420)
  }
}
