import Testing

@testable import GrokBotCore

@Test func nonOwnersReceiveNoPersonalTools() {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: false, conversationChatID: 1, conversationKey: "one",
    isGroup: false)
  #expect(toolbox.definitions(context: context, configuration: .init()).isEmpty)
}

@Test func nonOwnerCannotBypassPlanningAndExecutePersonalToolDirectly() async {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: false, conversationChatID: 1,
    conversationKey: "one", isGroup: false)
  let call = XAIFunctionCall(callID: "c1", name: "list_reminder_lists", arguments: [:])
  await #expect(
    throws: ToolArgumentError.invalid("Personal tools require a currently authorized owner.")
  ) {
    _ = try await toolbox.execute(call: call, context: context)
  }
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

@Test func reminderApprovalSummariesShowEveryMutationFieldAndStayBounded() {
  let toolbox = BotToolbox(messages: MockMessages(), reminders: MockReminders())
  let context = ToolContext(
    requesterHandle: "+1", requesterIsOwner: true, conversationChatID: 1,
    conversationKey: "one", isGroup: false)
  let create = XAIFunctionCall(
    callID: "create", name: "create_reminder",
    arguments: [
      "title": .string("Ship\nrelease"),
      "list_name": .string("Work"),
      "notes": .string(String(repeating: "n", count: 500)),
      "due_at": .string("2026-09-01T16:00:00Z"),
    ])
  let update = XAIFunctionCall(
    callID: "update", name: "update_reminder",
    arguments: [
      "id": .string("reminder-1"),
      "title": .string("New title"),
      "notes": .string("New notes"),
      "due_at": .string("2026-09-02T16:00:00Z"),
      "clear_due_date": .bool(false),
      "completed": .bool(true),
    ])

  guard
    case .requiresApproval(let createSummary) = toolbox.plan(
      call: create, context: context, configuration: .init())
  else {
    Issue.record("Expected create approval")
    return
  }
  #expect(createSummary.contains("title “Ship release”"))
  #expect(createSummary.contains("list “Work”"))
  #expect(createSummary.contains("notes “"))
  #expect(createSummary.contains("due “2026-09-01T16:00:00Z”"))
  #expect(createSummary.count <= 900)

  guard
    case .requiresApproval(let updateSummary) = toolbox.plan(
      call: update, context: context, configuration: .init())
  else {
    Issue.record("Expected update approval")
    return
  }
  #expect(updateSummary.contains("ID “reminder-1”"))
  #expect(updateSummary.contains("title “New title”"))
  #expect(updateSummary.contains("notes “New notes”"))
  #expect(updateSummary.contains("due “2026-09-02T16:00:00Z”"))
  #expect(updateSummary.contains("clear due date: false"))
  #expect(updateSummary.contains("completed: true"))
}
