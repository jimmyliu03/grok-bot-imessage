import SwiftUI

struct DashboardView: View {
  @Bindable var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Dashboard").font(.largeTitle.bold())
            Text("Your private Grok gateway on this Mac.").foregroundStyle(.secondary)
          }
          Spacer()
          Button(model.status == .running ? "Stop Bot" : "Start Bot") {
            Task { await model.toggleGateway() }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(model.status == .running ? .red : .purple)
          .disabled(model.status == .starting)
          .accessibilityIdentifier("toggle-gateway")
        }

        statusHero

        if !model.pendingApprovals.isEmpty || !model.pairingRequests.isEmpty {
          AttentionView(model: model)
        }

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
        Circle().fill((model.status == .running ? Color.green : Color.secondary).opacity(0.15))
        Image(systemName: model.status == .running ? "bolt.horizontal.fill" : "pause.fill")
          .font(.system(size: 30))
          .foregroundStyle(model.status == .running ? .green : .secondary)
      }
      .frame(width: 72, height: 72)
      VStack(alignment: .leading, spacing: 5) {
        Text(model.status.title).font(.title2.bold())
        Text(
          model.status.detail
            ?? (model.status == .running
              ? "Watching approved iMessage conversations" : "Start when setup checks are ready")
        )
        .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(model.configuration.model).font(.headline)
        Text("xAI Responses API").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(22)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private var readiness: some View {
    DashboardCard(title: "Readiness", icon: "checklist") {
      ReadinessRow(title: "xAI API key", ready: model.hasAPIKey)
      ReadinessRow(title: "imsg installed", ready: model.imsgInstalled)
      ReadinessRow(title: "Messages readable", ready: model.messagesReady)
      ReadinessRow(title: "Reminders", ready: model.remindersStatus == .fullAccess)
      ReadinessRow(
        title: "Owner configured",
        ready: !model.configuration.ownerHandles.isEmpty
          || !model.configuration.ownerSelfChatIDs.isEmpty)
    }
  }

  private var safety: some View {
    DashboardCard(title: "Safety defaults", icon: "lock.shield") {
      Label("Unknown senders are ignored", systemImage: "person.crop.circle.badge.xmark")
      Label("Group chats are off", systemImage: "person.3.sequence")
      Label("Writes need an approval code", systemImage: "checkmark.shield")
      Label("API key stays in Keychain", systemImage: "key")
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
      Label("Needs your attention", systemImage: "bell.badge.fill").font(.headline).foregroundStyle(
        .orange)
      ForEach(model.pendingApprovals) { approval in
        HStack {
          VStack(alignment: .leading) {
            Text(approval.summary).fontWeight(.medium)
            Text("Requested by \(approval.requesterHandle)").font(.caption).foregroundStyle(
              .secondary)
          }
          Spacer()
          Button("Deny") { Task { await model.resolveApproval(approval, approved: false) } }
            .disabled(model.status != .running)
          Button("Approve") { Task { await model.resolveApproval(approval, approved: true) } }
            .buttonStyle(.borderedProminent)
            .disabled(model.status != .running)
        }
      }
      ForEach(model.pairingRequests) { request in
        HStack {
          VStack(alignment: .leading) {
            Text("Pair \(request.handle)?").fontWeight(.medium)
            Text("Code \(request.code)").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Ignore") { Task { await model.rejectPairing(request) } }
          Button("Allow") { Task { await model.approvePairing(request) } }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(18)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3)))
  }
}
