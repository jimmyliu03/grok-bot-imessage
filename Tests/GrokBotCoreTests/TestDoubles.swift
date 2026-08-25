import EventKit
import Foundation

@testable import GrokBotCore

final class MockMessages: IMsgServicing, @unchecked Sendable {
  struct Sent: Equatable {
    let chatID: Int?
    let recipient: String?
    let text: String
    let service: String?
  }

  private let lock = NSLock()
  var chats: [IMsgChat] = []
  var histories: [Int: [IMsgMessage]] = [:]
  private var sentStorage: [Sent] = []
  private(set) var lastUnreadOnly = false

  var sent: [Sent] { lock.withLock { sentStorage } }

  func databaseIdentity() async -> String? { "mock-db" }

  func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws {}

  func stop() async {}

  func listChats(limit: Int, unreadOnly: Bool) async throws -> [IMsgChat] {
    lastUnreadOnly = unreadOnly
    let values = unreadOnly ? chats.filter { $0.unreadCount > 0 } : chats
    return Array(values.prefix(limit))
  }

  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage] {
    Array((histories[chatID] ?? []).prefix(limit))
  }

  func send(chatID: Int, text: String) async throws {
    lock.withLock {
      sentStorage.append(.init(chatID: chatID, recipient: nil, text: text, service: nil))
    }
  }

  func send(to recipient: String, text: String, service: String) async throws {
    lock.withLock {
      sentStorage.append(.init(chatID: nil, recipient: recipient, text: text, service: service))
    }
  }
}

final class MockReminders: RemindersServicing, @unchecked Sendable {
  private let lock = NSLock()
  var status: EKAuthorizationStatus = .fullAccess
  var listValues = [
    ReminderListRecord(id: "personal", title: "Personal"),
    ReminderListRecord(id: "work", title: "Work"),
  ]
  var reminderValues = [
    ReminderRecord(
      id: "r1", title: "Allowed", notes: nil, list: "Personal", listID: "personal",
      dueAt: nil,
      isCompleted: false),
    ReminderRecord(
      id: "r2", title: "Private", notes: nil, list: "Work", listID: "work",
      dueAt: nil,
      isCompleted: false),
  ]
  private var createdStorage: [ReminderRecord] = []
  private var deletedStorage: [String] = []

  var created: [ReminderRecord] { lock.withLock { createdStorage } }
  var deleted: [String] { lock.withLock { deletedStorage } }

  func authorizationStatus() async -> EKAuthorizationStatus { status }
  func requestAccess() async throws -> Bool { true }
  func lists() async throws -> [ReminderListRecord] { listValues }

  func reminders(
    listID: String?, listName: String?, includeCompleted: Bool, dueBefore: Date?
  ) async throws -> [ReminderRecord] {
    reminderValues.filter {
      (listID == nil || $0.listID == listID)
        && (listName == nil || $0.list.caseInsensitiveCompare(listName!) == .orderedSame)
        && (includeCompleted || !$0.isCompleted)
    }
  }

  func reminder(id: String) async throws -> ReminderRecord {
    guard let value = reminderValues.first(where: { $0.id == id }) else {
      throw RemindersError.reminderNotFound(id)
    }
    return value
  }

  func create(
    title: String, notes: String?, listID: String?, listName: String?, dueAt: Date?
  ) async throws -> ReminderRecord {
    let resolvedListID = listID ?? "personal"
    let resolvedListName =
      listName ?? listValues.first(where: { $0.id == resolvedListID })?.title
      ?? "Personal"
    let value = ReminderRecord(
      id: "new", title: title, notes: notes, list: resolvedListName, listID: resolvedListID,
      dueAt: nil, isCompleted: false)
    lock.withLock { createdStorage.append(value) }
    return value
  }

  func update(
    id: String, title: String?, notes: String?, dueAt: Date?, clearDueDate: Bool,
    completed: Bool?
  ) async throws -> ReminderRecord {
    let existing = try await reminder(id: id)
    return ReminderRecord(
      id: id,
      title: title ?? existing.title,
      notes: notes ?? existing.notes,
      list: existing.list,
      listID: existing.listID,
      dueAt: nil,
      isCompleted: completed ?? existing.isCompleted
    )
  }

  func delete(id: String) async throws {
    lock.withLock { deletedStorage.append(id) }
  }
}

final class ApprovalRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [BridgePendingApproval] = []

  var values: [BridgePendingApproval] { lock.withLock { storage } }
  func record(_ values: [BridgePendingApproval]) { lock.withLock { storage = values } }
}

actor BlockingMessages: IMsgServicing {
  private var startContinuation: CheckedContinuation<Void, Error>?
  private var entered = false

  func databaseIdentity() async -> String? { "blocking-db" }

  func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws {
    entered = true
    try await withCheckedThrowingContinuation { startContinuation = $0 }
  }

  func stop() async {
    startContinuation?.resume(throwing: IMsgError.notRunning)
    startContinuation = nil
  }

  func listChats(limit: Int, unreadOnly: Bool) async throws -> [IMsgChat] { [] }
  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage] { [] }
  func send(chatID: Int, text: String) async throws {}
  func send(to recipient: String, text: String, service: String) async throws {}
  func hasEntered() -> Bool { entered }
}

final class BridgeEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [BridgeEvent] = []

  var values: [BridgeEvent] { lock.withLock { storage } }
  func record(_ value: BridgeEvent) { lock.withLock { storage.append(value) } }
}
