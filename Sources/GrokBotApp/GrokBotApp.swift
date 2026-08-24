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
      CommandMenu("Bot") {
        Button(model.status == .running ? "Stop Grok Bot" : "Start Grok Bot") {
          Task { await model.toggleGateway() }
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])
      }
    }

    MenuBarExtra {
      MenuBarContent(model: model)
    } label: {
      Label(
        "Grok Bot",
        systemImage: model.status == .running
          ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
    }

    Settings {
      SettingsView(model: model)
    }
  }
}
