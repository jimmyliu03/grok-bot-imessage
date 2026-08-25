import GrokBotCore
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    if model.onboardingComplete {
      NavigationSplitView {
        List(AppModel.Page.allCases, selection: $model.selection) { page in
          Label(page.rawValue, systemImage: page.icon)
            .tag(page)
        }
        .navigationTitle("Mac Bridge")
        .safeAreaInset(edge: .bottom) {
          SidebarStatus(model: model)
        }
      } detail: {
        page
      }
      .navigationSplitViewStyle(.balanced)
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
    } else {
      OnboardingView(model: model)
    }
  }

  @ViewBuilder
  private var page: some View {
    switch model.selection ?? .dashboard {
    case .dashboard: DashboardView(model: model)
    case .access: AccessView(model: model)
    case .scopes: PeopleView(model: model)
    case .activity: ActivityView(model: model)
    }
  }
}

private struct SidebarStatus: View {
  @Bindable var model: AppModel

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(model.status.isRunning ? .green : .secondary)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.status.title)
          .font(.caption.weight(.semibold))
        Text("Mac Bridge")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(12)
    .background(.bar)
  }
}

extension BridgeStatus {
  var title: String {
    switch self {
    case .stopped: "Stopped"
    case .starting: "Starting…"
    case .running: "Running"
    case .failed: "Needs attention"
    }
  }

  var detail: String? {
    guard case .failed(let value) = self else { return nil }
    return value
  }
}

#Preview("Configured app") {
  RootView(model: AppModel())
    .frame(width: 1040, height: 720)
}
