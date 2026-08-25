import SwiftUI

struct ActivityView: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      if !model.pendingApprovals.isEmpty {
        ScrollView { AttentionView(model: model).padding() }
          .frame(maxHeight: 260)
        Divider()
      }
      if model.activity.isEmpty {
        ContentUnavailableView(
          "No activity yet",
          systemImage: "waveform.path.ecg",
          description: Text(
            "Connector status and tool names appear here. Message bodies, reminder text, and connector tokens are never logged."
          )
        )
      } else {
        List(model.activity) { entry in
          HStack(alignment: .firstTextBaseline) {
            Text(entry.date, format: .dateTime.hour().minute().second())
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
            Text(entry.text)
          }
        }
      }
    }
    .navigationTitle("Activity")
  }
}
