import AppKit
import SwiftUI

struct MenuBarContent: View {
  @Bindable var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text("Grok Bot: \(model.status.title)")
    if !model.pendingApprovals.isEmpty {
      Text("\(model.pendingApprovals.count) action approval(s) waiting")
    }
    Divider()
    Button("Open Dashboard") {
      openWindow(id: "dashboard")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button(model.status == .running ? "Stop Bot" : "Start Bot") {
      Task { await model.toggleGateway() }
    }
    .disabled(model.status == .starting)
    SettingsLink { Text("Settings…") }
    Divider()
    Button("Quit Grok Bot") { NSApp.terminate(nil) }
  }
}
