import EventKit
import SwiftUI

struct AccessView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Grok API") {
        LabeledContent("xAI API key") {
          HStack {
            SecureField(model.hasAPIKey ? "Saved in Keychain" : "xai-…", text: $model.apiKeyDraft)
              .frame(minWidth: 280)
            Button("Save") { model.saveAPIKey() }
              .disabled(model.apiKeyDraft.isEmpty)
            if model.hasAPIKey {
              Button("Remove", role: .destructive) { model.removeAPIKey() }
            }
          }
        }
        Text(
          "The key is stored in macOS Keychain. Owner prompts and selected tool results use xAI's stateful Responses API so approved actions can continue; API content may be retained under your xAI account's data controls (typically up to 30 days)."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Messages bridge") {
        LabeledContent("imsg command") {
          HStack {
            StatusPill(
              label: model.imsgInstalled ? "Installed" : "Missing", ready: model.imsgInstalled)
            if !model.imsgInstalled {
              Button("Copy Install Command") { model.prepareIMsgInstall() }
            }
          }
        }
        if let path = model.imsgPath {
          LabeledContent("Verified executable") {
            Text(path).font(.caption.monospaced()).textSelection(.enabled)
          }
        }
        LabeledContent("Full Disk Access") {
          HStack {
            StatusPill(
              label: model.messagesReady ? "Messages readable" : "Required",
              ready: model.messagesReady)
            Button("Open Settings") { model.openFullDiskAccess() }
          }
        }
        LabeledContent("Messages automation") {
          Button("Open Settings") { model.openAutomationAccess() }
        }
        Text(
          "Basic reading and watching use read-only access to ~/Library/Messages/chat.db. Sending is pinned to Messages.app AppleScript automation. Grok Bot resolves imsg only from Homebrew's standard locations, does not enable private-API mode, and does not require SIP changes."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Reminders") {
        LabeledContent("Read and write access") {
          HStack {
            StatusPill(
              label: model.remindersStatus.label, ready: model.remindersStatus == .fullAccess)
            if model.remindersStatus == .notDetermined {
              Button("Request Access") { Task { await model.requestRemindersAccess() } }
            } else if model.remindersStatus != .fullAccess {
              Button("Open Settings") { model.openRemindersAccess() }
            }
          }
        }
        Toggle(
          "Expose Reminders tools to owner sessions", isOn: $model.configuration.remindersEnabled)
      }

      Section {
        Button("Recheck all access") { Task { await model.refreshEnvironment() } }
          .disabled(model.isChecking)
        Button("Save Settings") { model.saveConfiguration() }
          .buttonStyle(.borderedProminent)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Access")
  }
}
