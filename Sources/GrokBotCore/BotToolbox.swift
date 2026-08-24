import Foundation

public struct ToolContext: Equatable, Sendable {
  public let requesterHandle: String
  public let requesterIsOwner: Bool
  public let conversationChatID: Int
  public let conversationKey: String
  public let isGroup: Bool

  public init(
    requesterHandle: String,
    requesterIsOwner: Bool,
    conversationChatID: Int,
    conversationKey: String,
    isGroup: Bool
  ) {
    self.requesterHandle = requesterHandle
    self.requesterIsOwner = requesterIsOwner
    self.conversationChatID = conversationChatID
    self.conversationKey = conversationKey
    self.isGroup = isGroup
  }
}

public enum ToolInvocationPlan: Equatable, Sendable {
  case execute
  case requiresApproval(summary: String)
  case reject(reason: String)
}

public protocol BotTooling: Sendable {
  func definitions(context: ToolContext, configuration: BotConfiguration) -> [XAIToolDefinition]
  func plan(call: XAIFunctionCall, context: ToolContext, configuration: BotConfiguration)
    -> ToolInvocationPlan
  func execute(call: XAIFunctionCall, context: ToolContext) async throws -> JSONValue
}

public final class BotToolbox: BotTooling, @unchecked Sendable {
  private let messages: IMsgServicing
  private let reminders: RemindersServicing

  public init(messages: IMsgServicing, reminders: RemindersServicing) {
    self.messages = messages
    self.reminders = reminders
  }

  public func definitions(context: ToolContext, configuration: BotConfiguration)
    -> [XAIToolDefinition]
  {
    guard context.requesterIsOwner else { return [] }
    var tools: [XAIToolDefinition] = []
    if configuration.remindersEnabled { tools += Self.reminderDefinitions }
    if configuration.messageToolsEnabled { tools += Self.messageDefinitions }
    return tools
  }

  public func plan(
    call: XAIFunctionCall,
    context: ToolContext,
    configuration: BotConfiguration
  ) -> ToolInvocationPlan {
    guard context.requesterIsOwner else {
      return .reject(
        reason: "Personal tools are available only to an owner configured in Grok Bot.")
    }
    let reminderNames = Set(Self.reminderDefinitions.map(\.name))
    let messageNames = Set(Self.messageDefinitions.map(\.name))
    guard reminderNames.contains(call.name) || messageNames.contains(call.name) else {
      return .reject(reason: "Unknown tool: \(call.name)")
    }
    if reminderNames.contains(call.name), !configuration.remindersEnabled {
      return .reject(reason: "Reminder tools are disabled.")
    }
    if messageNames.contains(call.name), !configuration.messageToolsEnabled {
      return .reject(reason: "Message tools are disabled.")
    }
    guard Self.mutatingTools.contains(call.name) else { return .execute }
    if configuration.toolApprovalMode == .trustedOwners { return .execute }
    return .requiresApproval(summary: approvalSummary(call: call))
  }

  public func execute(call: XAIFunctionCall, context: ToolContext) async throws -> JSONValue {
    switch call.name {
    case "list_reminder_lists":
      return try encode(await reminders.lists())
    case "list_reminders":
      let list = call.arguments.string("list_name")
      let completed = call.arguments.bool("include_completed") ?? false
      let dueBefore = try optionalDate(call.arguments.string("due_before"))
      return try encode(
        await reminders.reminders(listName: list, includeCompleted: completed, dueBefore: dueBefore)
      )
    case "create_reminder":
      let title = try requiredString("title", in: call.arguments)
      let date = try optionalDate(call.arguments.string("due_at"))
      return try encode(
        await reminders.create(
          title: title,
          notes: call.arguments.string("notes"),
          listName: call.arguments.string("list_name"),
          dueAt: date
        ))
    case "update_reminder":
      let id = try requiredString("id", in: call.arguments)
      let date = try optionalDate(call.arguments.string("due_at"))
      return try encode(
        await reminders.update(
          id: id,
          title: call.arguments.string("title"),
          notes: call.arguments.string("notes"),
          dueAt: date,
          clearDueDate: call.arguments.bool("clear_due_date") ?? false,
          completed: call.arguments.bool("completed")
        ))
    case "delete_reminder":
      let id = try requiredString("id", in: call.arguments)
      try await reminders.delete(id: id)
      return .object(["ok": .bool(true)])
    case "list_imessage_chats":
      return try encode(await messages.listChats(limit: call.arguments.int("limit") ?? 20))
    case "read_imessage_history":
      let chatID = try requiredInt("chat_id", in: call.arguments)
      let values = try await messages.history(
        chatID: chatID, limit: call.arguments.int("limit") ?? 20)
      let redacted = values.map {
        IMsgHistoryRecord(
          id: $0.id,
          sender: $0.senderName ?? $0.sender ?? ($0.isFromMe ? "Me" : "Unknown"),
          isFromMe: $0.isFromMe,
          text: $0.text,
          createdAt: $0.createdAt
        )
      }
      return try encode(redacted)
    case "send_imessage":
      let text = try requiredString("text", in: call.arguments)
      let chatID = call.arguments.int("chat_id")
      let recipient = call.arguments.string("recipient")
      guard (chatID == nil) != (recipient == nil) else {
        throw ToolArgumentError.invalid("Provide exactly one of recipient or chat_id.")
      }
      if let chatID {
        try await messages.send(chatID: chatID, text: text)
      } else {
        try await messages.send(to: requiredString("recipient", in: call.arguments), text: text)
      }
      return .object(["ok": .bool(true)])
    default:
      throw ToolArgumentError.unknownTool(call.name)
    }
  }

  private func approvalSummary(call: XAIFunctionCall) -> String {
    switch call.name {
    case "send_imessage":
      let destination =
        call.arguments.string("recipient") ?? call.arguments.int("chat_id").map { "chat \($0)" }
        ?? "an unknown recipient"
      return "Send “\(call.arguments.string("text") ?? "")” to \(destination)"
    case "create_reminder":
      return "Create reminder “\(call.arguments.string("title") ?? "Untitled")”"
    case "update_reminder":
      return "Update reminder \(call.arguments.string("id") ?? "")"
    case "delete_reminder":
      return "Delete reminder \(call.arguments.string("id") ?? "")"
    default:
      return "Run \(call.name)"
    }
  }

  private func requiredString(_ key: String, in values: [String: JSONValue]) throws -> String {
    guard let value = values.string(key),
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ToolArgumentError.missing(key)
    }
    return value
  }

  private func requiredInt(_ key: String, in values: [String: JSONValue]) throws -> Int {
    guard let value = values.int(key) else { throw ToolArgumentError.missing(key) }
    return value
  }

  private func optionalDate(_ value: String?) throws -> Date? {
    guard let value else { return nil }
    guard let date = ISO8601DateFormatter.grokBotDate(from: value) else {
      throw RemindersError.invalidDate(value)
    }
    return date
  }

  private func encode<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }

  private static let mutatingTools: Set<String> = [
    "create_reminder", "update_reminder", "delete_reminder", "send_imessage",
  ]

  private static let reminderDefinitions: [XAIToolDefinition] = [
    .init(
      name: "list_reminder_lists", description: "List the owner's Apple Reminders lists.",
      parameters: objectSchema([:])),
    .init(
      name: "list_reminders",
      description: "Read reminders, optionally filtered by list and due date.",
      parameters: objectSchema([
        "list_name": stringSchema("Exact reminder list name."),
        "include_completed": boolSchema("Whether completed reminders should be returned."),
        "due_before": stringSchema("ISO 8601 upper bound for due date."),
      ])),
    .init(
      name: "create_reminder",
      description: "Create a reminder. This is a write action that may require approval.",
      parameters: objectSchema(
        [
          "title": stringSchema("Reminder title."),
          "notes": stringSchema("Optional notes."),
          "list_name": stringSchema("Exact reminder list name; omit for the default list."),
          "due_at": stringSchema("Optional ISO 8601 due date and time."),
        ], required: ["title"])),
    .init(
      name: "update_reminder",
      description: "Update or complete an existing reminder by ID. This may require approval.",
      parameters: objectSchema(
        [
          "id": stringSchema("Stable reminder ID from list_reminders."),
          "title": stringSchema("New title."),
          "notes": stringSchema("New notes."),
          "due_at": stringSchema("New ISO 8601 due date and time."),
          "clear_due_date": boolSchema("Set true to remove the due date."),
          "completed": boolSchema("New completion state."),
        ], required: ["id"])),
    .init(
      name: "delete_reminder",
      description: "Delete a reminder by ID. This destructive action requires approval by default.",
      parameters: objectSchema(
        [
          "id": stringSchema("Stable reminder ID from list_reminders.")
        ], required: ["id"])),
  ]

  private static let messageDefinitions: [XAIToolDefinition] = [
    .init(
      name: "list_imessage_chats", description: "List recent iMessage chats on the owner's Mac.",
      parameters: objectSchema([
        "limit": integerSchema("Number of chats, from 1 to 100.")
      ])),
    .init(
      name: "read_imessage_history",
      description: "Read recent text from one iMessage chat by numeric chat ID.",
      parameters: objectSchema(
        [
          "chat_id": integerSchema("Chat ID returned by list_imessage_chats."),
          "limit": integerSchema("Number of messages, from 1 to 100."),
        ], required: ["chat_id"])),
    .init(
      name: "send_imessage",
      description:
        "Send a text through Messages to one recipient or an existing chat. This requires approval by default.",
      parameters: objectSchema(
        [
          "recipient": stringSchema("Phone number or Apple ID email. Omit when chat_id is used."),
          "chat_id": integerSchema(
            "Existing chat ID, preferred for groups. Omit when recipient is used."),
          "text": stringSchema("Plain-text message to send."),
        ], required: ["text"])),
  ]

  private static func objectSchema(_ properties: [String: JSONValue], required: [String] = [])
    -> JSONValue
  {
    .object([
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
      "additionalProperties": .bool(false),
    ])
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object(["type": .string("string"), "description": .string(description)])
  }

  private static func boolSchema(_ description: String) -> JSONValue {
    .object(["type": .string("boolean"), "description": .string(description)])
  }

  private static func integerSchema(_ description: String) -> JSONValue {
    .object(["type": .string("integer"), "description": .string(description)])
  }
}

private struct IMsgHistoryRecord: Encodable {
  let id: Int
  let sender: String
  let isFromMe: Bool
  let text: String?
  let createdAt: String?

  enum CodingKeys: String, CodingKey {
    case id, sender, text
    case isFromMe = "is_from_me"
    case createdAt = "created_at"
  }
}

public enum ToolArgumentError: LocalizedError, Equatable {
  case missing(String)
  case invalid(String)
  case unknownTool(String)

  public var errorDescription: String? {
    switch self {
    case .missing(let key): return "Tool argument “\(key)” is required."
    case .invalid(let message): return message
    case .unknownTool(let name): return "Unknown tool “\(name)”."
    }
  }
}
