import AppKit
import SwiftUI

struct MenuBarContent: View {
  @Bindable var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text("Mac Bridge: \(model.status.title)")
    if !model.pendingApprovals.isEmpty {
      Text("\(model.pendingApprovals.count) local approval(s) waiting")
    }
    Divider()
    Button("Open Dashboard") {
      openWindow(id: "dashboard")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button(model.status.isRunning ? "Stop Bridge" : "Start Bridge") {
      Task { await model.toggleBridge() }
    }
    .disabled(model.status == .starting)
    SettingsLink { Text("Settings…") }
    Divider()
    Button("Quit Mac Bridge") { NSApp.terminate(nil) }
  }
}
