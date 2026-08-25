import GrokBotCore
import SwiftUI

struct DashboardView: View {
  @Bindable var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Dashboard").font(.largeTitle.bold())
            Text("Your private Apple services bridge for Grok Bot.").foregroundStyle(.secondary)
          }
          Spacer()
          Button(model.status.isRunning ? "Stop Bridge" : "Start Bridge") {
            Task { await model.toggleBridge() }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(model.status.isRunning ? .red : .purple)
          .disabled(model.status == .starting)
          .accessibilityIdentifier("toggle-bridge")
        }

        statusHero

        if !model.pendingApprovals.isEmpty {
          AttentionView(model: model)
        }

        connector

        HStack(alignment: .top, spacing: 16) {
          readiness
          safety
        }
      }
      .padding(30)
    }
    .navigationTitle("Dashboard")
    .toolbar {
      Button {
        Task { await model.refreshEnvironment() }
      } label: {
        Label("Recheck Access", systemImage: "arrow.clockwise")
      }
      .disabled(model.isChecking)
    }
  }

  private var statusHero: some View {
    HStack(spacing: 20) {
      ZStack {
        Circle().fill((model.status.isRunning ? Color.green : Color.secondary).opacity(0.15))
        Image(systemName: model.status.isRunning ? "link.circle.fill" : "pause.fill")
          .font(.system(size: 30))
          .foregroundStyle(model.status.isRunning ? .green : .secondary)
      }
      .frame(width: 72, height: 72)
      VStack(alignment: .leading, spacing: 5) {
        Text(model.status.title).font(.title2.bold())
        Text(
          model.status.detail
            ?? (model.status.isRunning
              ? "Grok Bot can call the enabled MCP tools" : "Start the bridge after setup is ready")
        )
        .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text("127.0.0.1:\(model.configuration.port)").font(.headline.monospacedDigit())
        Text("Streamable HTTP MCP").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(22)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var connector: some View {
    DashboardCard(title: "Grok Bot connector", icon: "point.3.connected.trianglepath.dotted") {
      TextField("Public HTTPS tunnel URL", text: $model.configuration.publicBaseURL)
        .textFieldStyle(.roundedBorder)
      if let url = model.publicConnectorURL {
        Text(url)
          .font(.caption.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
          .privacySensitive()
      } else {
        Text("Paste the HTTPS URL from cloudflared or your stable tunnel.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Copy Tunnel Command") { model.copyTunnelCommand() }
        Button("Copy Private Connector URL") { model.copyConnectorURL() }
          .disabled(model.publicConnectorURL == nil)
        Button("Open Grok Connectors") { model.openGrokConnectors() }
        Spacer()
        Button("Save") { model.saveConfiguration() }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private var readiness: some View {
    DashboardCard(title: "Readiness", icon: "checklist") {
      ReadinessRow(title: "Connector token in Keychain", ready: !model.connectorToken.isEmpty)
      if model.configuration.messagesEnabled {
        ReadinessRow(title: "imsg installed", ready: model.imsgInstalled)
        ReadinessRow(title: "Messages readable", ready: model.messagesReady)
      }
      if model.configuration.remindersEnabled {
        ReadinessRow(title: "Reminders allowed", ready: model.remindersStatus == .fullAccess)
      }
      ReadinessRow(title: "Access scope selected", ready: model.configuredAccess)
    }
  }

  private var safety: some View {
    DashboardCard(title: "Safety", icon: "lock.shield") {
      Label(messageScopeLabel, systemImage: "message.badge")
      Label(reminderScopeLabel, systemImage: "checklist")
      Label(writePolicyLabel, systemImage: "checkmark.shield")
      Label("Server listens on loopback only", systemImage: "network.badge.shield.half.filled")
    }
  }

  private var messageScopeLabel: String {
    guard model.configuration.messagesEnabled else { return "Messages tools disabled" }
    if model.configuration.messageAccessMode == .allChats { return "All Messages chats allowed" }
    return "\(model.configuration.allowedChatIDs.count) Messages chat(s) selected"
  }

  private var reminderScopeLabel: String {
    guard model.configuration.remindersEnabled else { return "Reminders tools disabled" }
    if model.configuration.reminderAccessMode == .allLists { return "All reminder lists allowed" }
    return "\(model.configuration.allowedReminderListIDs.count) reminder list(s) selected"
  }

  private var writePolicyLabel: String {
    switch model.configuration.writeApprovalMode {
    case .localApproval: "Writes need local approval"
    case .trustGrokBot: "Trust Grok Bot write approvals"
    }
  }
}

private struct DashboardCard<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Label(title, systemImage: icon).font(.headline)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.background, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.5)))
  }
}

private struct ReadinessRow: View {
  let title: String
  let ready: Bool

  var body: some View {
    HStack {
      Image(systemName: ready ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(ready ? .green : .secondary)
      Text(title)
      Spacer()
    }
  }
}

struct AttentionView: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Local approval required", systemImage: "bell.badge.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text("Approve once, then ask Grok Bot to retry the exact same action within ten minutes.")
        .font(.caption).foregroundStyle(.secondary)
      ForEach(model.pendingApprovals) { approval in
        HStack {
          VStack(alignment: .leading) {
            Text(approval.summary).fontWeight(.medium)
            Text(approval.toolName).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Deny") { Task { await model.deny(approval) } }
          Button("Approve Once") { Task { await model.approve(approval) } }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(18)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3)))
  }
}
