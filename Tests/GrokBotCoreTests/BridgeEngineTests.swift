import Foundation
import Testing

@testable import GrokBotCore

@Test func stopWhileStartingCannotReopenBridge() async {
  let messages = BlockingMessages()
  let events = BridgeEventRecorder()
  let engine = BridgeEngine(
    configuration: .init(),
    token: "test-token",
    messages: messages,
    reminders: MockReminders(),
    eventSink: { events.record($0) }
  )

  let start = Task { await engine.start() }
  for _ in 0..<100 {
    if await messages.hasEntered() { break }
    try? await Task.sleep(for: .milliseconds(5))
  }
  #expect(await messages.hasEntered())
  await engine.stop()
  await start.value

  let statuses = events.values.compactMap { event -> BridgeStatus? in
    if case .status(let status) = event { return status }
    return nil
  }
  #expect(statuses.last == .stopped)
  #expect(
    !events.values.contains { event in
      if case .status(.running) = event { return true }
      return false
    })
}
