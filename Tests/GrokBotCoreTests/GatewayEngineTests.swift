import Foundation
import Testing

@testable import GrokBotCore

@Test func gatewayRepliesOnlyToAllowedOwnerAndPersistsCursor() async throws {
  let messages = MockMessages()
  let client = ScriptedXAIClient([
    .success(.init(id: "r1", outputText: "Hi owner", functionCalls: []))
  ])
  let store = InMemoryGatewayStateStore(state: .init(lastMessageRowID: 10))
  let config = BotConfiguration(ownerHandles: ["+14155551212"])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: config, messages: messages, toolLoop: loop, stateStore: store)

  await engine.start()
  #expect(messages.startCursor == 10)
  messages.emit(.init(id: 11, chatID: 1, guid: "unknown", sender: "+14155550000", text: "Hi"))
  try? await Task.sleep(nanoseconds: 80_000_000)
  #expect(messages.sent.isEmpty)

  messages.emit(.init(id: 12, chatID: 2, guid: "owner", sender: "+14155551212", text: "Hi"))
  #expect(await eventually { messages.sent.count == 1 })
  #expect(messages.sent.first?.text == "Hi owner")
  #expect(try store.load().lastMessageRowID == 12)
  await engine.stop()
}

@Test func staleReplayIsSkippedButCursorAdvances() async throws {
  let messages = MockMessages()
  let store = InMemoryGatewayStateStore()
  let config = BotConfiguration(ownerHandles: ["+14155551212"])
  let client = ScriptedXAIClient([])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: config, messages: messages, toolLoop: loop, stateStore: store)
  await engine.start()
  let old = ISO8601DateFormatter.grokBot.string(from: Date().addingTimeInterval(-10_000))
  messages.emit(
    .init(id: 4, chatID: 1, guid: "old", sender: "+14155551212", text: "Old", createdAt: old))
  #expect(await eventually { (try? store.load().lastMessageRowID) == 4 })
  #expect(messages.sent.isEmpty)
  #expect(client.calls.isEmpty)
  await engine.stop()
}

@Test func botEchoDoesNotCreateSelfChatLoop() async throws {
  let messages = MockMessages()
  let config = BotConfiguration(ownerSelfChatIDs: [8])
  let client = ScriptedXAIClient([
    .success(.init(id: "r1", outputText: "Bot reply", functionCalls: []))
  ])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: config, messages: messages, toolLoop: loop,
    stateStore: InMemoryGatewayStateStore())
  await engine.start()
  messages.emit(.init(id: 1, chatID: 8, guid: "user", isFromMe: true, text: "Hello"))
  #expect(await eventually { messages.sent.count == 1 })
  messages.emit(.init(id: 2, chatID: 8, guid: "bot-echo", isFromMe: true, text: "Bot reply"))
  try? await Task.sleep(nanoseconds: 100_000_000)
  #expect(messages.sent.count == 1)
  #expect(client.calls.count == 1)
  await engine.stop()
}

@Test func nonOwnerGrokSessionGetsNoPersonalTools() async throws {
  let messages = MockMessages()
  let config = BotConfiguration(
    directMessagePolicy: .allowlist, allowedSenders: ["+14155550000"],
    ownerHandles: ["+14155551212"])
  let client = ScriptedXAIClient([
    .success(.init(id: "r1", outputText: "Hello guest", functionCalls: []))
  ])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: config, messages: messages, toolLoop: loop,
    stateStore: InMemoryGatewayStateStore())
  await engine.start()
  messages.emit(.init(id: 1, chatID: 3, guid: "guest", sender: "+14155550000", text: "Hello"))
  #expect(await eventually { messages.sent.count == 1 })
  #expect(client.calls.first?.toolNames.isEmpty == true)
  await engine.stop()
}

@Test func replacedMessagesDatabaseResetsReplayCursor() async throws {
  let messages = MockMessages()
  messages.identity = "new-db"
  let state = PersistedGatewayState(
    processedGUIDs: ["old-guid"],
    messagesDatabaseIdentity: "old-db",
    lastMessageRowID: 9_999
  )
  let store = InMemoryGatewayStateStore(state: state)
  let client = ScriptedXAIClient([])
  let loop = GrokToolLoop(
    client: client,
    apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders())
  )
  let engine = GatewayEngine(
    configuration: BotConfiguration(ownerHandles: ["+14155551212"]),
    messages: messages,
    toolLoop: loop,
    stateStore: store
  )

  await engine.start()
  #expect(messages.startCursor == nil)
  #expect(try store.load().processedGUIDs.isEmpty)
  #expect(try store.load().messagesDatabaseIdentity == "new-db")
  await engine.stop()
}
