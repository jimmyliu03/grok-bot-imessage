import Testing

@testable import GrokBotCore

private let ownerContext = ToolContext(
  requesterHandle: "+14155551212",
  requesterIsOwner: true,
  conversationChatID: 9,
  conversationKey: "chat-9",
  isGroup: false
)

@Test func directGrokMessageReturnsWithoutToolCalls() async throws {
  let client = ScriptedXAIClient([
    .success(.init(id: "r1", outputText: "Hello!", functionCalls: []))
  ])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: MockMessages(), reminders: MockReminders()))
  let result = try await loop.respond(
    userText: "Hi", history: [], context: ownerContext, configuration: .init())
  #expect(result == .message("Hello!"))
  #expect(client.calls.first?.toolNames.contains("send_imessage") == true)
}

@Test func readToolRunsAndFeedsResultBackToGrok() async throws {
  let client = ScriptedXAIClient([
    .success(
      .init(
        id: "r1", outputText: nil,
        functionCalls: [.init(callID: "call-1", name: "list_reminder_lists", arguments: [:])])),
    .success(.init(id: "r2", outputText: "You have a Reminders list.", functionCalls: [])),
  ])
  let loop = GrokToolLoop(
    client: client, apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: MockMessages(), reminders: MockReminders()))
  let result = try await loop.respond(
    userText: "What lists?", history: [], context: ownerContext, configuration: .init())
  #expect(result == .message("You have a Reminders list."))
  #expect(client.calls.count == 2)
  #expect(client.calls[1].previousResponseID == "r1")
  #expect(client.calls[1].functionOutput?.callID == "call-1")
}

@Test func reminderWritePausesThenContinuesAfterApproval() async throws {
  let client = ScriptedXAIClient([
    .success(
      .init(
        id: "r1", outputText: nil,
        functionCalls: [
          .init(
            callID: "call-1",
            name: "create_reminder",
            arguments: ["title": .string("Ship release")]
          )
        ])),
    .success(.init(id: "r2", outputText: "Done.", functionCalls: [])),
  ])
  let reminders = MockReminders()
  let loop = GrokToolLoop(
    client: client,
    apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: MockMessages(), reminders: reminders),
    codeGenerator: { "123456" }
  )
  let first = try await loop.respond(
    userText: "Remind me to ship", history: [], context: ownerContext, configuration: .init())
  guard case .approvalRequired(let approval) = first else {
    Issue.record("Expected approval")
    return
  }
  #expect(approval.code == "123456")
  #expect(reminders.createdTitles.isEmpty)
  let second = try await loop.continueApproval(
    approval, approved: true, context: ownerContext, configuration: .init())
  #expect(second == .message("Done."))
  #expect(reminders.createdTitles == ["Ship release"])
  #expect(client.calls[1].previousResponseID == "r1")
}
