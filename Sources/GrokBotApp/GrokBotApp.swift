import GrokBotCore
import SwiftUI

@main
struct GrokBotApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup(id: "dashboard") {
      RootView(model: model)
        .frame(minWidth: 880, minHeight: 620)
    }
    .defaultSize(width: 1040, height: 720)
    .commands {
      SidebarCommands()
      CommandMenu("Bridge") {
        Button(model.status.isRunning ? "Stop Mac Bridge" : "Start Mac Bridge") {
          Task { await model.toggleBridge() }
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])
      }
    }

    MenuBarExtra {
      MenuBarContent(model: model)
    } label: {
      Label(
        "Mac Bridge",
        systemImage: model.status.isRunning
          ? "point.3.filled.connected.trianglepath.dotted" : "point.3.connected.trianglepath.dotted"
      )
    }

    Settings {
      SettingsView(model: model)
    }
  }
}
