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

@Test func pairingRepliesOnlyOncePerLiveRequestAndExpiredRequestsCannotBeApproved() async throws {
  let messages = MockMessages()
  let request = PairingRequest(
    code: "123456", handle: "+14155550001", chatID: 8,
    expiresAt: Date().addingTimeInterval(0.04))
  let store = InMemoryGatewayStateStore(state: .init(pairingRequests: [request]))
  let loop = GrokToolLoop(
    client: ScriptedXAIClient([]), apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: BotConfiguration(directMessagePolicy: .pairing),
    messages: messages,
    toolLoop: loop,
    stateStore: store)
  await engine.start()

  messages.emit(
    .init(id: 1, chatID: 3, guid: "pair-1", sender: "+14155550000", text: "Hello"))
  messages.emit(
    .init(id: 2, chatID: 3, guid: "pair-2", sender: "+14155550000", text: "Again"))
  #expect(await eventually { messages.sent.count == 1 })
  try? await Task.sleep(nanoseconds: 70_000_000)
  #expect(await engine.approvePairing(id: request.id) == nil)
  #expect(messages.sent.count == 1)
  await engine.stop()
}

@Test func messagesDatabaseReplacementClearsEveryChatBoundStateAndConfiguration() async throws {
  let messages = MockMessages()
  messages.identity = "new-db"
  let pairing = PairingRequest(code: "123456", handle: "+1", chatID: 8)
  let approval = PendingApproval(
    code: "654321", chatID: 8, requesterHandle: "self", toolName: "create_reminder",
    arguments: ["title": .string("Private")], summary: "Create", responseID: "response",
    callID: "call", model: "grok-4.6", conversationKey: "chat-8")
  let store = InMemoryGatewayStateStore(
    state: .init(
      sessions: ["chat-8": [.init(role: .user, text: "private context")]],
      pairingRequests: [pairing], pendingApprovals: [approval], processedGUIDs: ["old"],
      botSentFingerprints: [.init(chatID: 8, text: "old reply")],
      messagesDatabaseIdentity: "old-db", lastMessageRowID: 999))
  let recorder = EventRecorder()
  let loop = GrokToolLoop(
    client: ScriptedXAIClient([]), apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: BotConfiguration(allowedGroupChatIDs: [7], ownerSelfChatIDs: [8]),
    messages: messages, toolLoop: loop, stateStore: store,
    eventSink: { recorder.record($0) })

  await engine.start()
  let reset = try store.load()
  #expect(reset.sessions.isEmpty)
  #expect(reset.pairingRequests.isEmpty)
  #expect(reset.pendingApprovals.isEmpty)
  #expect(reset.processedGUIDs.isEmpty)
  #expect(reset.botSentFingerprints.isEmpty)
  #expect(reset.lastMessageRowID == nil)
  #expect(reset.messagesDatabaseIdentity == "new-db")
  #expect(
    recorder.events.contains {
      guard case .configurationReset(let configuration) = $0 else { return false }
      return configuration.allowedGroupChatIDs.isEmpty && configuration.ownerSelfChatIDs.isEmpty
    })
  await engine.stop()
}

@Test func stoppingGatewayRevokesAnInFlightToolCall() async {
  let messages = MockMessages()
  let client = BlockingXAIClient(
    response: .init(
      id: "response", outputText: nil,
      functionCalls: [
        .init(
          callID: "send", name: "send_imessage",
          arguments: ["recipient": .string("+14155550000"), "text": .string("Do not send")])
      ]))
  var configuration = BotConfiguration(ownerHandles: ["+14155551212"])
  configuration.toolApprovalMode = .trustedOwners
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: configuration, messages: messages, toolLoop: loop,
    stateStore: InMemoryGatewayStateStore())
  await engine.start()
  messages.emit(
    .init(id: 1, chatID: 1, guid: "in-flight", sender: "+14155551212", text: "Send it"))
  #expect(await eventually { await client.hasEntered() })

  await engine.stop()
  await client.release()
  try? await Task.sleep(nanoseconds: 80_000_000)
  #expect(messages.sent.isEmpty)
}

@Test func terminalWatchFailureReconnectsFromTheSafeCursor() async throws {
  let messages = MockMessages()
  let store = InMemoryGatewayStateStore(state: .init(lastMessageRowID: 10))
  let recorder = EventRecorder()
  let loop = GrokToolLoop(
    client: ScriptedXAIClient([]), apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: BotConfiguration(ownerHandles: ["+14155551212"]), messages: messages,
    toolLoop: loop, stateStore: store, eventSink: { recorder.record($0) })
  await engine.start()

  messages.fail(
    IMsgError.watchTerminated(message: "overflow", resumeAfterRowID: 42))
  #expect(await eventually(timeout: 2.5) { messages.startCount >= 2 })
  #expect(try store.load().lastMessageRowID == 42)
  #expect(messages.startCursor == 42)
  #expect(recorder.events.contains(.status(.failed("overflow"))))
  await engine.stop()
}

@Test func stopDuringStartupNeverTransitionsToRunning() async {
  let messages = BlockingStartMessages()
  let recorder = EventRecorder()
  let loop = GrokToolLoop(
    client: ScriptedXAIClient([]), apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders()))
  let engine = GatewayEngine(
    configuration: BotConfiguration(ownerHandles: ["+14155551212"]), messages: messages,
    toolLoop: loop, stateStore: InMemoryGatewayStateStore(),
    eventSink: { recorder.record($0) })
  let startTask = Task { await engine.start() }
  #expect(await eventually { await messages.hasEntered() })
  await engine.stop()
  await messages.releaseStart()
  await startTask.value

  let statuses = recorder.events.compactMap { event -> GatewayStatus? in
    guard case .status(let status) = event else { return nil }
    return status
  }
  #expect(statuses.last == .stopped)
  #expect(!statuses.contains(.running))
}
