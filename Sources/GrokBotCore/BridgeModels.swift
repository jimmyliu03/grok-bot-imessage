import Foundation

public enum MessageAccessMode: String, Codable, CaseIterable, Sendable {
  case selectedChats
  case allChats
}

public enum ReminderAccessMode: String, Codable, CaseIterable, Sendable {
  case selectedLists
  case allLists
}

public enum BridgeWriteApprovalMode: String, Codable, CaseIterable, Sendable {
  case localApproval
  case trustGrokBot
}

public struct BridgeConfiguration: Codable, Equatable, Sendable {
  public var port: UInt16
  public var publicBaseURL: String
  public var messagesEnabled: Bool
  public var remindersEnabled: Bool
  public var messageAccessMode: MessageAccessMode
  public var allowedChatIDs: [Int]
  public var allowNewRecipients: Bool
  public var allowedRecipients: [String]
  public var reminderAccessMode: ReminderAccessMode
  public var allowedReminderListIDs: [String]
  public var writeApprovalMode: BridgeWriteApprovalMode
  public var launchAtLogin: Bool
  public var messagesDatabaseIdentity: String?

  public init(
    port: UInt16 = 29_333,
    publicBaseURL: String = "",
    messagesEnabled: Bool = true,
    remindersEnabled: Bool = true,
    messageAccessMode: MessageAccessMode = .selectedChats,
    allowedChatIDs: [Int] = [],
    allowNewRecipients: Bool = false,
    allowedRecipients: [String] = [],
    reminderAccessMode: ReminderAccessMode = .selectedLists,
    allowedReminderListIDs: [String] = [],
    writeApprovalMode: BridgeWriteApprovalMode = .localApproval,
    launchAtLogin: Bool = true,
    messagesDatabaseIdentity: String? = nil
  ) {
    self.port = port
    self.publicBaseURL = publicBaseURL
    self.messagesEnabled = messagesEnabled
    self.remindersEnabled = remindersEnabled
    self.messageAccessMode = messageAccessMode
    self.allowedChatIDs = allowedChatIDs
    self.allowNewRecipients = allowNewRecipients
    self.allowedRecipients = allowedRecipients
    self.reminderAccessMode = reminderAccessMode
    self.allowedReminderListIDs = allowedReminderListIDs
    self.writeApprovalMode = writeApprovalMode
    self.launchAtLogin = launchAtLogin
    self.messagesDatabaseIdentity = messagesDatabaseIdentity
  }

  public func permitsChat(_ chatID: Int) -> Bool {
    messageAccessMode == .allChats || allowedChatIDs.contains(chatID)
  }

  public func permitsRecipient(_ recipient: String) -> Bool {
    allowNewRecipients
      || allowedRecipients.contains {
        Self.normalizedHandle($0) == Self.normalizedHandle(recipient)
      }
  }

  public func permitsReminderList(id: String) -> Bool {
    reminderAccessMode == .allLists || allowedReminderListIDs.contains(id)
  }

  public static func normalizedHandle(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.contains("@") { return trimmed }
    let digits = trimmed.filter(\.isNumber)
    return digits.isEmpty ? trimmed : "+" + digits
  }
}

public enum BridgeStatus: Equatable, Sendable {
  case stopped
  case starting
  case running(port: UInt16)
  case failed(String)
}

public struct BridgePendingApproval: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let toolName: String
  public let arguments: [String: JSONValue]
  public let summary: String
  public let createdAt: Date
  public let expiresAt: Date

  public init(
    id: UUID = UUID(),
    toolName: String,
    arguments: [String: JSONValue],
    summary: String,
    createdAt: Date = Date(),
    expiresAt: Date = Date().addingTimeInterval(600)
  ) {
    self.id = id
    self.toolName = toolName
    self.arguments = arguments
    self.summary = summary
    self.createdAt = createdAt
    self.expiresAt = expiresAt
  }
}

public enum BridgeEvent: Equatable, Sendable {
  case status(BridgeStatus)
  case activity(String)
  case approvals([BridgePendingApproval])
  case toolCompleted(String)
}

public struct MCPToolDefinition: Equatable, Sendable {
  public let name: String
  public let description: String
  public let inputSchema: JSONValue
  public let annotations: JSONValue?

  public init(
    name: String,
    description: String,
    inputSchema: JSONValue,
    annotations: JSONValue? = nil
  ) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.annotations = annotations
  }

  public var json: JSONValue {
    var value: [String: JSONValue] = [
      "name": .string(name),
      "description": .string(description),
      "inputSchema": inputSchema,
    ]
    if let annotations { value["annotations"] = annotations }
    return .object(value)
  }
}

public enum BridgeToolError: LocalizedError, Equatable {
  case unknownTool(String)
  case missing(String)
  case invalid(String)
  case disabled(String)
  case accessDenied(String)
  case approvalRequired(UUID, String)

  public var errorDescription: String? {
    switch self {
    case .unknownTool(let value): return "Unknown tool: \(value)"
    case .missing(let value): return "Missing required argument: \(value)"
    case .invalid(let value): return value
    case .disabled(let value): return value
    case .accessDenied(let value): return value
    case .approvalRequired(let id, let summary):
      return
        "Local approval required for \(summary). Open Grok Bot Mac Bridge, approve request \(id.uuidString), then retry this exact tool call."
    }
  }
}
