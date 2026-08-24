import Testing

@testable import GrokBotCore

@Test func nonOwnersReceiveNoPersonalTools() {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: false, conversationChatID: 1, conversationKey: "one",
    isGroup: false)
  #expect(toolbox.definitions(context: context, configuration: .init()).isEmpty)
}

@Test func messageAndReminderWritesRequireApprovalByDefault() {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: true, conversationChatID: 1, conversationKey: "one",
    isGroup: false)
  let send = XAIFunctionCall(
    callID: "c1", name: "send_imessage",
    arguments: ["recipient": .string("+2"), "text": .string("Hi")])
  let create = XAIFunctionCall(
    callID: "c2", name: "create_reminder", arguments: ["title": .string("Ship")])
  guard case .requiresApproval = toolbox.plan(call: send, context: context, configuration: .init())
  else {
    Issue.record("send_imessage should require approval")
    return
  }
  guard
    case .requiresApproval = toolbox.plan(call: create, context: context, configuration: .init())
  else {
    Issue.record("create_reminder should require approval")
    return
  }
}

@Test func readsExecuteWithoutApprovalForOwners() {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: true, conversationChatID: 1, conversationKey: "one",
    isGroup: false)
  let read = XAIFunctionCall(callID: "c1", name: "list_reminder_lists", arguments: [:])
  #expect(toolbox.plan(call: read, context: context, configuration: .init()) == .execute)
}

@Test func sendRequiresExactlyOneDestination() async {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: true, conversationChatID: 1, conversationKey: "one",
    isGroup: false)
  let call = XAIFunctionCall(
    callID: "c1", name: "send_imessage",
    arguments: [
      "recipient": .string("+2"), "chat_id": .number(3), "text": .string("Hi"),
    ])
  await #expect(throws: ToolArgumentError.invalid("Provide exactly one of recipient or chat_id.")) {
    _ = try await toolbox.execute(call: call, context: context)
  }
}
