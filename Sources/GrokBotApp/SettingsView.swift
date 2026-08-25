import GrokBotCore
import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    TabView {
      Form {
        Toggle("Launch Mac Bridge at login", isOn: $model.configuration.launchAtLogin)
        Toggle("Enable Messages tools", isOn: $model.configuration.messagesEnabled)
        Toggle("Enable Reminders tools", isOn: $model.configuration.remindersEnabled)
        TextField("Public tunnel URL", text: $model.configuration.publicBaseURL)
        HStack {
          Button("Run Setup Again") { model.showOnboarding() }
          Spacer()
          Button("Save") { model.saveConfiguration() }.buttonStyle(.borderedProminent)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("General", systemImage: "gear") }

      Form {
        Picker("Write approvals", selection: $model.configuration.writeApprovalMode) {
          Text("Require local approval").tag(BridgeWriteApprovalMode.localApproval)
          Text("Trust Grok Bot approvals").tag(BridgeWriteApprovalMode.trustGrokBot)
        }
        Text(
          "Local approval is recommended. Reads still obey the chat and reminder-list scopes configured in the main app."
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button("Save") { model.saveConfiguration() }.buttonStyle(.borderedProminent)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("Safety", systemImage: "lock.shield") }
    }
    .frame(width: 560, height: 360)
  }
}
