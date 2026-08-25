import EventKit
import SwiftUI

struct AccessView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Messages bridge") {
        LabeledContent("imsg command") {
          HStack {
            StatusPill(
              label: model.imsgInstalled ? "Installed" : "Missing",
              ready: model.imsgInstalled
            )
            if !model.imsgInstalled {
              Button("Install") { model.prepareIMsgInstall() }
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
              ready: model.messagesReady
            )
            Button("Open Settings") { model.openFullDiskAccess() }
          }
        }
        LabeledContent("Messages automation") {
          Button("Open Settings") { model.openAutomationAccess() }
        }
        Text(
          "Reading uses read-only access to ~/Library/Messages/chat.db. Sending uses Messages.app AppleScript automation. The app only accepts canonical Homebrew imsg installations and never requires SIP changes."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Reminders") {
        LabeledContent("Read and write access") {
          HStack {
            StatusPill(
              label: model.remindersStatus.label,
              ready: model.remindersStatus == .fullAccess
            )
            if model.remindersStatus == .notDetermined {
              Button("Request Access") { Task { await model.requestRemindersAccess() } }
            } else if model.remindersStatus != .fullAccess {
              Button("Open Settings") { model.openRemindersAccess() }
            }
          }
        }
      }

      Section("Local MCP server") {
        LabeledContent("Listen address") {
          Text("127.0.0.1")
            .font(.body.monospaced())
        }
        LabeledContent("Port") {
          TextField("Port", value: $model.configuration.port, format: .number)
            .frame(width: 100)
            .textFieldStyle(.roundedBorder)
        }
        LabeledContent("Connector token") {
          HStack {
            Text("••••••••\(model.connectorToken.suffix(6))")
              .font(.body.monospaced())
            Button("Rotate") { Task { await model.rotateConnectorToken() } }
          }
        }
        Text(
          "The token is a 256-bit secret stored in Keychain. The server binds only to loopback; your HTTPS tunnel forwards authenticated MCP requests to it. Rotating the token immediately invalidates old connector URLs."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section {
        Button("Recheck all access") { Task { await model.refreshEnvironment() } }
          .disabled(model.isChecking)
        Button("Save Settings") { model.saveConfiguration() }
          .buttonStyle(.borderedProminent)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Apple Access")
  }
}
