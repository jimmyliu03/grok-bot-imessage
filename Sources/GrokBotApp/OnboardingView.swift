import EventKit
import SwiftUI

struct OnboardingView: View {
  @Bindable var model: AppModel

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        hero
        VStack(spacing: 14) {
          SetupCard(
            number: 1, title: "Connect Grok", subtitle: "Your API key stays in macOS Keychain.",
            complete: model.hasAPIKey
          ) {
            HStack {
              SecureField(
                model.hasAPIKey ? "Replace xAI API key" : "xai-…", text: $model.apiKeyDraft
              )
              .textFieldStyle(.roundedBorder)
              .accessibilityIdentifier("xai-api-key")
              Button("Save") { model.saveAPIKey() }
                .buttonStyle(.borderedProminent)
                .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Link(
              "Create an API key at console.x.ai",
              destination: URL(string: "https://console.x.ai/")!
            )
            .font(.caption)
          }

          SetupCard(
            number: 2, title: "Connect Messages",
            subtitle: "Grok Bot uses the open-source imsg bridge locally—no webhook or relay.",
            complete: model.imsgInstalled && model.messagesReady
          ) {
            HStack {
              StatusPill(label: "imsg", ready: model.imsgInstalled)
              StatusPill(label: "Messages data", ready: model.messagesReady)
              Spacer()
              if !model.imsgInstalled {
                Button(model.isInstallingIMsg ? "Installing…" : "Install imsg") {
                  Task { await model.installIMsg() }
                }
                .disabled(model.isInstallingIMsg)
              }
              Button("Full Disk Access") { model.openFullDiskAccess() }
              Button("Recheck") { Task { await model.refreshEnvironment() } }
            }
            Text(
              "After enabling Full Disk Access for Grok Bot, quit and reopen the app. macOS will ask for Messages automation the first time the bot sends."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          SetupCard(
            number: 3, title: "Choose the owner",
            subtitle: "Only owners can access private Messages and Reminders tools.",
            complete: !model.configuration.ownerHandles.isEmpty
              || !model.configuration.ownerSelfChatIDs.isEmpty
          ) {
            HandlesField(
              title: "Your iMessage phone number or Apple ID email",
              placeholder: "+14155551212, you@icloud.com",
              values: $model.configuration.ownerHandles
            )
            Label(
              "Best setup: sign this Mac into a dedicated iMessage account for the bot, then add your personal number here.",
              systemImage: "lightbulb"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          SetupCard(
            number: 4, title: "Allow Reminders",
            subtitle: "EventKit provides read/write access after macOS consent.",
            complete: model.remindersStatus == .fullAccess
          ) {
            HStack {
              StatusPill(
                label: model.remindersStatus.label, ready: model.remindersStatus == .fullAccess)
              Spacer()
              if model.remindersStatus == .notDetermined {
                Button("Allow Reminders") { Task { await model.requestRemindersAccess() } }
                  .buttonStyle(.borderedProminent)
              } else if model.remindersStatus != .fullAccess {
                Button("Open Privacy Settings") { model.openRemindersAccess() }
              }
            }
          }
        }

        HStack {
          Text("\(model.checklistReadyCount) of 5 setup checks complete")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Finish Setup") { model.finishOnboarding() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canStart)
            .accessibilityIdentifier("finish-setup")
        }
      }
      .frame(maxWidth: 760)
      .padding(40)
      .frame(maxWidth: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .alert(
      "Grok Bot",
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
      Image(systemName: "bolt.horizontal.circle.fill")
        .font(.system(size: 58))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.purple)
      Text("Meet Grok Bot for iMessage")
        .font(.largeTitle.bold())
      Text("An always-on, local-first Grok gateway for Messages and Reminders.")
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

struct HandlesField: View {
  let title: String
  let placeholder: String
  @Binding var values: [String]

  var body: some View {
    LabeledContent(title) {
      TextField(
        placeholder,
        text: Binding(
          get: { values.joined(separator: ", ") },
          set: { values = Self.parse($0) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .frame(minWidth: 320)
    }
  }

  private static func parse(_ raw: String) -> [String] {
    raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
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

#Preview("First run") {
  OnboardingView(model: AppModel())
    .frame(width: 920, height: 760)
}
