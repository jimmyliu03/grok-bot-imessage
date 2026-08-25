import GrokBotCore
import SwiftUI

struct PeopleView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Messages reading") {
        Toggle("Enable Messages tools", isOn: $model.configuration.messagesEnabled)
        if model.configuration.messagesEnabled {
          Picker("Readable chats", selection: $model.configuration.messageAccessMode) {
            Text("Selected chats only").tag(MessageAccessMode.selectedChats)
            Text("All chats").tag(MessageAccessMode.allChats)
          }
          if model.configuration.messageAccessMode == .selectedChats {
            ScopeSelectionList(
              values: model.recentChats,
              selected: $model.configuration.allowedChatIDs
            )
            Button("Load Recent Chats") { Task { await model.refreshChats() } }
          }
          Text(
            "Grok Bot only sees chat metadata and history returned by the tools. The connector does not upload your whole Messages database."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }

      Section("Starting new conversations") {
        Toggle(
          "Allow any phone number or Apple ID email",
          isOn: $model.configuration.allowNewRecipients
        )
        if !model.configuration.allowNewRecipients {
          LabeledContent("Allowed recipients") {
            TextField(
              "+14155551212, person@icloud.com",
              text: Binding(
                get: { model.configuration.allowedRecipients.joined(separator: ", ") },
                set: { model.configuration.allowedRecipients = Self.parseRecipients($0) }
              )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 360)
          }
        }
        Text(
          "Sending to an existing chat follows the readable-chat scope. Enter phone numbers in E.164 form (+country code). Use service=auto to let Messages choose iMessage or SMS."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Reminders") {
        Toggle("Enable Reminders tools", isOn: $model.configuration.remindersEnabled)
        if model.configuration.remindersEnabled {
          Picker("Accessible lists", selection: $model.configuration.reminderAccessMode) {
            Text("Selected lists only").tag(ReminderAccessMode.selectedLists)
            Text("All lists").tag(ReminderAccessMode.allLists)
          }
          if model.configuration.reminderAccessMode == .selectedLists {
            ReminderScopeSelectionList(
              values: model.reminderLists,
              selected: $model.configuration.allowedReminderListIDs
            )
            Button("Load Reminder Lists") { Task { await model.refreshReminderLists() } }
          }
        }
      }

      Section("Write approvals") {
        Picker("Policy", selection: $model.configuration.writeApprovalMode) {
          Text("Require approval in this Mac app").tag(BridgeWriteApprovalMode.localApproval)
          Text("Trust Grok Bot approvals").tag(BridgeWriteApprovalMode.trustGrokBot)
        }
        Text(
          "Local approval is safest: the first write is blocked, you approve it here, and Grok Bot retries the exact call once. Trust mode is smoother for routines but relies on Grok Bot's approval rules."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Spacer()
          Button("Save Access Policy") { model.saveConfiguration() }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Data Scopes")
    .task {
      if model.recentChats.isEmpty, model.messagesReady { await model.refreshChats() }
      if model.reminderLists.isEmpty, model.remindersStatus == .fullAccess {
        await model.refreshReminderLists()
      }
    }
  }

  private static func parseRecipients(_ raw: String) -> [String] {
    raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
