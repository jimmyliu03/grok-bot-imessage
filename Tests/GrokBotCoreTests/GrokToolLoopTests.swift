import Foundation
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

@Test func executionGuardStopsToolAtTheLocalBoundary() async {
  let messages = MockMessages()
  let client = ScriptedXAIClient([
    .success(
      .init(
        id: "r1", outputText: nil,
        functionCalls: [
          .init(
            callID: "send-1", name: "send_imessage",
            arguments: ["recipient": .string("+14155550000"), "text": .string("Do not send")]
          )
        ]))
  ])
  let loop = GrokToolLoop(
    client: client,
    apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders())
  )
  var configuration = BotConfiguration()
  configuration.toolApprovalMode = .trustedOwners

  await #expect(throws: GrokToolLoopError.authorizationRevoked) {
    _ = try await loop.respond(
      userText: "Send it", history: [], context: ownerContext, configuration: configuration,
      executionGuard: { false })
  }
  #expect(messages.sent.isEmpty)
}

@Test func expiredApprovalCannotExecute() async {
  let reminders = MockReminders()
  let loop = GrokToolLoop(
    client: ScriptedXAIClient([]),
    apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: MockMessages(), reminders: reminders)
  )
  let approval = PendingApproval(
    code: "123456",
    chatID: ownerContext.conversationChatID,
    requesterHandle: ownerContext.requesterHandle,
    toolName: "create_reminder",
    arguments: ["title": .string("Too late")],
    summary: "Create reminder",
    responseID: "response",
    callID: "call",
    model: "grok-4.6",
    conversationKey: ownerContext.conversationKey,
    expiresAt: Date().addingTimeInterval(-1)
  )

  await #expect(throws: GrokToolLoopError.authorizationRevoked) {
    _ = try await loop.continueApproval(
      approval, approved: true, context: ownerContext, configuration: .init())
  }
  #expect(reminders.createdTitles.isEmpty)
}

@Test func uncertainIMsgDeliveryTerminatesTheToolChain() async {
  let messages = MockMessages()
  messages.sendError = IMsgError.rpc(
    code: -32_001,
    message: "Delivery confirmation timed out",
    retrySafe: false,
    disposition: "unknown")
  let client = ScriptedXAIClient([
    .success(
      .init(
        id: "r1", outputText: nil,
        functionCalls: [
          .init(
            callID: "send-1", name: "send_imessage",
            arguments: ["recipient": .string("+14155550000"), "text": .string("Maybe sent")]
          )
        ]))
  ])
  let loop = GrokToolLoop(
    client: client,
    apiKeys: StaticAPIKeyProvider("test"),
    tools: BotToolbox(messages: messages, reminders: MockReminders())
  )
  var configuration = BotConfiguration()
  configuration.toolApprovalMode = .trustedOwners

  do {
    _ = try await loop.respond(
      userText: "Send it", history: [], context: ownerContext, configuration: configuration)
    Issue.record("Expected an uncertain-delivery failure")
  } catch let error as GrokToolLoopError {
    guard case .mutationOutcomeUncertain(let message) = error else {
      Issue.record("Unexpected error: \(error)")
      return
    }
    #expect(message.contains("check Messages"))
  } catch {
    Issue.record("Unexpected error type: \(error)")
  }
  #expect(client.calls.count == 1)
}
