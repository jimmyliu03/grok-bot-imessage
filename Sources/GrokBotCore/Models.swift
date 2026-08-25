import Foundation

public struct IMsgChat: Codable, Identifiable, Equatable, Sendable {
  public let id: Int
  public let name: String?
  public let displayName: String?
  public let identifier: String?
  public let guid: String?
  public let service: String?
  public let isGroup: Bool
  public let participants: [String]
  public let lastMessageAt: String?
  public let unreadCount: Int

  enum CodingKeys: String, CodingKey {
    case id, name, identifier, guid, service, participants
    case displayName = "display_name"
    case isGroup = "is_group"
    case lastMessageAt = "last_message_at"
    case unreadCount = "unread_count"
  }

  public init(
    id: Int,
    name: String? = nil,
    displayName: String? = nil,
    identifier: String? = nil,
    guid: String? = nil,
    service: String? = nil,
    isGroup: Bool = false,
    participants: [String] = [],
    lastMessageAt: String? = nil,
    unreadCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.displayName = displayName
    self.identifier = identifier
    self.guid = guid
    self.service = service
    self.isGroup = isGroup
    self.participants = participants
    self.lastMessageAt = lastMessageAt
    self.unreadCount = unreadCount
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
    guid = try container.decodeIfPresent(String.self, forKey: .guid)
    service = try container.decodeIfPresent(String.self, forKey: .service)
    participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
    let explicitGroup: Bool? = try container.decodeIfPresent(Bool.self, forKey: .isGroup)
    isGroup = explicitGroup ?? (participants.count > 1)
    lastMessageAt = try container.decodeIfPresent(String.self, forKey: .lastMessageAt)
    unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
  }

  public var title: String {
    displayName ?? name ?? participants.joined(separator: ", ").nilIfEmpty ?? identifier
      ?? "Chat \(id)"
  }
}

public struct IMsgMessage: Codable, Equatable, Sendable {
  public let id: Int
  public let chatID: Int
  public let chatIdentifier: String?
  public let chatGUID: String?
  public let chatName: String?
  public let participants: [String]
  public let isGroup: Bool
  public let guid: String
  public let sender: String?
  public let senderName: String?
  public let isFromMe: Bool
  public let text: String?
  public let createdAt: String?
  public let isReaction: Bool

  enum CodingKeys: String, CodingKey {
    case id, guid, sender, text, participants
    case chatID = "chat_id"
    case chatIdentifier = "chat_identifier"
    case chatGUID = "chat_guid"
    case chatName = "chat_name"
    case isGroup = "is_group"
    case senderName = "sender_name"
    case isFromMe = "is_from_me"
    case createdAt = "created_at"
    case isReaction = "is_reaction"
  }

  public init(
    id: Int,
    chatID: Int,
    chatIdentifier: String? = nil,
    chatGUID: String? = nil,
    chatName: String? = nil,
    participants: [String] = [],
    isGroup: Bool = false,
    guid: String,
    sender: String? = nil,
    senderName: String? = nil,
    isFromMe: Bool = false,
    text: String? = nil,
    createdAt: String? = nil,
    isReaction: Bool = false
  ) {
    self.id = id
    self.chatID = chatID
    self.chatIdentifier = chatIdentifier
    self.chatGUID = chatGUID
    self.chatName = chatName
    self.participants = participants
    self.isGroup = isGroup
    self.guid = guid
    self.sender = sender
    self.senderName = senderName
    self.isFromMe = isFromMe
    self.text = text
    self.createdAt = createdAt
    self.isReaction = isReaction
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    chatID = try container.decode(Int.self, forKey: .chatID)
    chatIdentifier = try container.decodeIfPresent(String.self, forKey: .chatIdentifier)
    chatGUID = try container.decodeIfPresent(String.self, forKey: .chatGUID)
    chatName = try container.decodeIfPresent(String.self, forKey: .chatName)
    participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
    let explicitGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup)
    isGroup =
      explicitGroup ?? chatGUID?.contains(";+;") == true || chatIdentifier?.contains(";+;") == true
    guid = try container.decode(String.self, forKey: .guid)
    sender = try container.decodeIfPresent(String.self, forKey: .sender)
    senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
    isFromMe = try container.decodeIfPresent(Bool.self, forKey: .isFromMe) ?? false
    text = try container.decodeIfPresent(String.self, forKey: .text)
    createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    isReaction = try container.decodeIfPresent(Bool.self, forKey: .isReaction) ?? false
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
