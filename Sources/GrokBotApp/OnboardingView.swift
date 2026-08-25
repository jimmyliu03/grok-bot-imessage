import EventKit
import GrokBotCore
import SwiftUI

struct OnboardingView: View {
  @Bindable var model: AppModel

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        hero
        VStack(spacing: 14) {
          SetupCard(
            number: 1,
            title: "Connect Messages",
            subtitle:
              "The bridge uses imsg locally to read Messages and Messages.app automation to send. It never disables SIP or enables private Apple APIs.",
            complete: model.imsgInstalled && model.messagesReady
          ) {
            HStack {
              StatusPill(label: "imsg", ready: model.imsgInstalled)
              StatusPill(label: "Messages data", ready: model.messagesReady)
              Spacer()
              if !model.imsgInstalled {
                Button("Install imsg") { model.prepareIMsgInstall() }
              }
              Button("Full Disk Access") { model.openFullDiskAccess() }
              Button("Recheck") { Task { await model.refreshEnvironment() } }
            }
            Text(
              "macOS asks for Messages Automation on the first send. An iPhone with Text Message Forwarding is required when a recipient needs SMS."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          SetupCard(
            number: 2,
            title: "Allow Reminders",
            subtitle: "EventKit provides local read/write access after macOS consent.",
            complete: model.remindersStatus == .fullAccess
          ) {
            HStack {
              StatusPill(
                label: model.remindersStatus.label,
                ready: model.remindersStatus == .fullAccess
              )
              Spacer()
              if model.remindersStatus == .notDetermined {
                Button("Allow Reminders") { Task { await model.requestRemindersAccess() } }
                  .buttonStyle(.borderedProminent)
              } else if model.remindersStatus != .fullAccess {
                Button("Open Privacy Settings") { model.openRemindersAccess() }
              }
            }
          }

          SetupCard(
            number: 3,
            title: "Choose what Grok Bot may access",
            subtitle:
              "Start narrow. The bridge enforces these scopes even if a Bot or message asks for more.",
            complete: model.configuredAccess
          ) {
            Toggle("Enable Messages tools", isOn: $model.configuration.messagesEnabled)
            if model.configuration.messagesEnabled {
              Picker("Messages", selection: $model.configuration.messageAccessMode) {
                Text("Selected chats only").tag(MessageAccessMode.selectedChats)
                Text("All chats").tag(MessageAccessMode.allChats)
              }
              .pickerStyle(.segmented)
              if model.configuration.messageAccessMode == .selectedChats {
                ScopeSelectionList(
                  values: model.recentChats,
                  selected: $model.configuration.allowedChatIDs
                )
                Button("Load Recent Chats") { Task { await model.refreshChats() } }
              }
            }

            Divider()
            Toggle("Enable Reminders tools", isOn: $model.configuration.remindersEnabled)
            if model.configuration.remindersEnabled {
              Picker("Reminders", selection: $model.configuration.reminderAccessMode) {
                Text("Selected lists only").tag(ReminderAccessMode.selectedLists)
                Text("All lists").tag(ReminderAccessMode.allLists)
              }
              .pickerStyle(.segmented)
              if model.configuration.reminderAccessMode == .selectedLists {
                ReminderScopeSelectionList(
                  values: model.reminderLists,
                  selected: $model.configuration.allowedReminderListIDs
                )
                Button("Load Reminder Lists") { Task { await model.refreshReminderLists() } }
              }
            }
          }

          SetupCard(
            number: 4,
            title: "Connect Grok Bot",
            subtitle:
              "Grok requires a public HTTPS MCP URL. A Cloudflare quick tunnel is easiest for testing; use a named stable tunnel for an always-on setup.",
            complete: model.publicConnectorURL != nil
          ) {
            HStack {
              Button("Install cloudflared") { model.prepareTunnelInstall() }
              Button("Copy Tunnel Command") { model.copyTunnelCommand() }
            }
            TextField(
              "https://your-tunnel.example.com",
              text: $model.configuration.publicBaseURL
            )
            .textFieldStyle(.roundedBorder)
            if let connectorURL = model.publicConnectorURL {
              Text(connectorURL)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .privacySensitive()
              HStack {
                Button("Copy Private Connector URL") { model.copyConnectorURL() }
                  .buttonStyle(.borderedProminent)
                Button("Open Grok Connectors") { model.openGrokConnectors() }
              }
            }
            Text(
              "The private URL contains a 256-bit token stored in Keychain. Do not post it, commit it, or include it in screenshots."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        HStack {
          Text(
            model.canStart ? "Apple access is ready" : "Complete Apple access and choose a scope"
          )
          .foregroundStyle(.secondary)
          Spacer()
          Button("Finish Setup") { model.finishOnboarding() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canStart)
            .accessibilityIdentifier("finish-setup")
        }
      }
      .frame(maxWidth: 780)
      .padding(40)
      .frame(maxWidth: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .alert(
      "Grok Bot Mac Bridge",
      isPresented: Binding(
        get: { model.setupMessage != nil },
        set: { if !$0 { model.setupMessage = nil } }
      )
    ) {
      Button("OK") { model.setupMessage = nil }
    } message: {
      Text(model.setupMessage ?? "")
    }
  }

  private var hero: some View {
    VStack(spacing: 12) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.system(size: 58))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.purple)
      Text("Grok Bot Mac Bridge")
        .font(.largeTitle.bold())
      Text("Give your Grok Bot controlled access to Messages and Apple Reminders.")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }
}

private struct SetupCard<Content: View>: View {
  let number: Int
  let title: String
  let subtitle: String
  let complete: Bool
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      ZStack {
        Circle().fill(complete ? Color.green : Color.purple.opacity(0.15))
        if complete {
          Image(systemName: "checkmark").foregroundStyle(.white).fontWeight(.bold)
        } else {
          Text("\(number)").fontWeight(.bold).foregroundStyle(.purple)
        }
      }
      .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline)
          Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(18)
    .background(.background, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.6)))
  }
}

struct StatusPill: View {
  let label: String
  let ready: Bool

  var body: some View {
    Label(label, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
      .font(.caption.weight(.medium))
      .foregroundStyle(ready ? .green : .orange)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background((ready ? Color.green : Color.orange).opacity(0.1), in: Capsule())
  }
}

struct ScopeSelectionList: View {
  let values: [IMsgChat]
  @Binding var selected: [Int]

  var body: some View {
    if values.isEmpty {
      Text("Load recent chats, then select the conversations Grok Bot may inspect.")
        .font(.caption).foregroundStyle(.secondary)
    } else {
      ForEach(values.prefix(30)) { chat in
        Toggle(
          isOn: Binding(
            get: { selected.contains(chat.id) },
            set: { enabled in
              if enabled, !selected.contains(chat.id) { selected.append(chat.id) }
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

struct ReminderScopeSelectionList: View {
  let values: [ReminderListRecord]
  @Binding var selected: [String]

  var body: some View {
    if values.isEmpty {
      Text("Load lists, then select the reminder lists Grok Bot may use.")
        .font(.caption).foregroundStyle(.secondary)
    } else {
      ForEach(values, id: \.id) { list in
        Toggle(
          list.title,
          isOn: Binding(
            get: { selected.contains(list.id) },
            set: { enabled in
              if enabled, !selected.contains(list.id) { selected.append(list.id) }
              if !enabled { selected.removeAll { $0 == list.id } }
            }
          )
        )
      }
    }
  }
}

extension EKAuthorizationStatus {
  var label: String {
    switch self {
    case .notDetermined: "Not requested"
    case .restricted: "Restricted"
    case .denied: "Denied"
    case .authorized, .fullAccess: "Allowed"
    case .writeOnly: "Write only"
    @unknown default: "Unknown"
    }
  }
}
