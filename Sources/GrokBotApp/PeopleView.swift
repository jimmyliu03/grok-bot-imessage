import GrokBotCore
import SwiftUI

struct PeopleView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Owners") {
        HandlesField(
          title: "Owner handles",
          placeholder: "+14155551212, you@icloud.com",
          values: $model.configuration.ownerHandles
        )
        Text(
          "Owners can ask Grok to read Messages and manage Reminders. Normalize phone numbers to E.164 (+country code)."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Direct messages") {
        Picker("Access policy", selection: $model.configuration.directMessagePolicy) {
          Text("Owner & allowlist only").tag(DirectMessagePolicy.allowlist)
          Text("Pair new people").tag(DirectMessagePolicy.pairing)
          Text("Disabled").tag(DirectMessagePolicy.disabled)
        }
        HandlesField(
          title: "Additional people",
          placeholder: "+14155550000",
          values: $model.configuration.allowedSenders
        )
        Text(
          "Additional people can chat with Grok, but personal Messages and Reminders tools are never exposed to them."
        )
        .font(.caption).foregroundStyle(.secondary)
      }

      Section("Groups") {
        Picker("Group policy", selection: $model.configuration.groupMessagePolicy) {
          Text("Disabled").tag(GroupMessagePolicy.disabled)
          Text("Selected groups only").tag(GroupMessagePolicy.allowlist)
        }
        Toggle(
          "Require “Grok” in group messages", isOn: $model.configuration.requireMentionInGroups)
        if model.configuration.groupMessagePolicy == .allowlist {
          ChatsPicker(
            title: "Allowed groups",
            chats: model.recentChats.filter(\.isGroup),
            selected: $model.configuration.allowedGroupChatIDs
          )
        }
      }

      Section("Self-chat (advanced)") {
        Text(
          "If Messages uses the same Apple account on this Mac and your phone, select exactly one private self-chat. Grok Bot ignores all other outgoing messages and records its own replies to prevent loops."
        )
        .font(.caption).foregroundStyle(.secondary)
        ChatsPicker(
          title: "Owner self-chats",
          chats: model.recentChats.filter { !$0.isGroup },
          selected: $model.configuration.ownerSelfChatIDs,
          allowsMultipleSelection: false
        )
      }

      Section {
        HStack {
          Button("Load Recent Chats") { Task { await model.refreshChats() } }
          Spacer()
          Button("Save Settings") { model.saveConfiguration() }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("People & Chats")
    .task {
      if model.recentChats.isEmpty, model.messagesReady { await model.refreshChats() }
    }
  }
}

private struct ChatsPicker: View {
  let title: String
  let chats: [IMsgChat]
  @Binding var selected: [Int]
  var allowsMultipleSelection = true

  var body: some View {
    if chats.isEmpty {
      LabeledContent(title) { Text("Load recent chats first").foregroundStyle(.secondary) }
    } else {
      DisclosureGroup(title) {
        ForEach(chats) { chat in
          Toggle(
            isOn: Binding(
              get: { selected.contains(chat.id) },
              set: { enabled in
                if enabled, !selected.contains(chat.id) {
                  if allowsMultipleSelection {
                    selected.append(chat.id)
                  } else {
                    selected = [chat.id]
                  }
                }
                if !enabled { selected.removeAll { $0 == chat.id } }
              }
            )
          ) {
            VStack(alignment: .leading) {
              Text(chat.title)
              Text("Chat \(chat.id) · \(chat.participants.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
}
