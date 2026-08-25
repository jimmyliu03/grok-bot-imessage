import Testing

@testable import GrokBotCore

@Test func toolDefinitionsFollowEnabledIntegrations() {
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: MockReminders())
  var configuration = BridgeConfiguration()
  configuration.messagesEnabled = false
  let names = Set(toolbox.definitions(configuration: configuration).map(\.name))
  #expect(!names.contains("send_imessage"))
  #expect(names.contains("list_reminders"))
}

@Test func selectedChatScopeFiltersListsAndBlocksDirectReads() async throws {
  let messages = MockMessages()
  messages.chats = [
    IMsgChat(id: 1, displayName: "Allowed", unreadCount: 1),
    IMsgChat(id: 2, displayName: "Private", unreadCount: 1),
  ]
  let toolbox = BridgeToolbox(messages: messages, reminders: MockReminders())
  var configuration = BridgeConfiguration()
  configuration.allowedChatIDs = [1]

  let value = try await toolbox.call(
    name: "list_imessage_chats",
    arguments: ["unread_only": .bool(true)],
    configuration: configuration
  )
  #expect(value.arrayValue?.count == 1)
  #expect(messages.lastUnreadOnly)

  await #expect(
    throws: BridgeToolError.accessDenied(
      "Chat 2 is not allowed. Select it in Mac Bridge → Data Scopes first."
    )
  ) {
    _ = try await toolbox.call(
      name: "read_imessage_history",
      arguments: ["chat_id": .number(2)],
      configuration: configuration
    )
  }
}

@Test func newRecipientSendRequiresScopeAndLocalApproval() async throws {
  let messages = MockMessages()
  let approvals = ApprovalRecorder()
  let toolbox = BridgeToolbox(
    messages: messages,
    reminders: MockReminders(),
    approvalEventSink: { approvals.record($0) }
  )
  var configuration = BridgeConfiguration()
  configuration.allowedRecipients = ["+1 (415) 555-1212"]
  let arguments: [String: JSONValue] = [
    "recipient": .string("+14155551212"),
    "text": .string("Hello"),
    "service": .string("auto"),
  ]

  do {
    _ = try await toolbox.call(
      name: "send_imessage", arguments: arguments, configuration: configuration)
    Issue.record("Expected local approval")
  } catch let BridgeToolError.approvalRequired(id, _) {
    await toolbox.approve(id: id)
  }

  _ = try await toolbox.call(
    name: "send_imessage", arguments: arguments, configuration: configuration)
  #expect(
    messages.sent == [
      .init(chatID: nil, recipient: "+14155551212", text: "Hello", service: "auto")
    ])
  #expect(approvals.values.isEmpty)
}

@Test func reminderScopeFiltersReadsAndProtectsWrites() async throws {
  let reminders = MockReminders()
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: reminders)
  var configuration = BridgeConfiguration()
  configuration.messagesEnabled = false
  configuration.allowedReminderListIDs = ["personal"]
  configuration.writeApprovalMode = .trustGrokBot

  let listed = try await toolbox.call(
    name: "list_reminders", arguments: [:], configuration: configuration)
  #expect(listed.arrayValue?.count == 1)

  await #expect(
    throws: BridgeToolError.accessDenied(
      "Reminder list “Work” is not allowed. Select it in Mac Bridge → Data Scopes first."
    )
  ) {
    _ = try await toolbox.call(
      name: "delete_reminder",
      arguments: ["id": .string("r2")],
      configuration: configuration
    )
  }
}

@Test func blockedWriteDoesNotCreateAnApprovalRequest() async {
  let approvals = ApprovalRecorder()
  let toolbox = BridgeToolbox(
    messages: MockMessages(),
    reminders: MockReminders(),
    approvalEventSink: { approvals.record($0) }
  )
  let configuration = BridgeConfiguration()

  await #expect(
    throws: BridgeToolError.accessDenied(
      "That recipient is not allowed. Add it in Mac Bridge → Data Scopes first."
    )
  ) {
    _ = try await toolbox.call(
      name: "send_imessage",
      arguments: [
        "recipient": .string("+14155550199"),
        "text": .string("This must not become approvable"),
      ],
      configuration: configuration
    )
  }
  #expect(approvals.values.isEmpty)
}

@Test func createWithoutListUsesOnlySelectedList() async throws {
  let reminders = MockReminders()
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: reminders)
  var configuration = BridgeConfiguration()
  configuration.allowedReminderListIDs = ["personal"]
  configuration.writeApprovalMode = .trustGrokBot

  _ = try await toolbox.call(
    name: "create_reminder",
    arguments: ["title": .string("Call the dentist")],
    configuration: configuration
  )
  #expect(reminders.created.first?.list == "Personal")
}

@Test func duplicateReminderListNamesRequireStableID() async {
  let reminders = MockReminders()
  reminders.listValues = [
    ReminderListRecord(id: "work-a", title: "Work"),
    ReminderListRecord(id: "work-b", title: "Work"),
  ]
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: reminders)
  var configuration = BridgeConfiguration()
  configuration.allowedReminderListIDs = ["work-a", "work-b"]

  await #expect(
    throws: BridgeToolError.invalid(
      "More than one allowed reminder list is named “Work”. Use list_id."
    )
  ) {
    _ = try await toolbox.call(
      name: "list_reminders",
      arguments: ["list_name": .string("Work")],
      configuration: configuration
    )
  }
}
