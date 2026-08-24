import EventKit
import Foundation

@testable import GrokBotCore

final class MockMessages: IMsgServicing, @unchecked Sendable {
  struct Sent: Equatable {
    let chatID: Int?
    let recipient: String?
    let text: String
  }
  private let lock = NSLock()
  private var handler: (@Sendable (IMsgMessage) -> Void)?
  private var failureHandler: (@Sendable (Error) -> Void)?
  private(set) var startCursor: Int?
  private var startCountStorage = 0
  private var sentStorage: [Sent] = []
  var chats: [IMsgChat] = []
  var histories: [Int: [IMsgMessage]] = [:]
  var identity = "mock-db"
  var sendError: Error?

  var sent: [Sent] { lock.withLock { sentStorage } }
  var startCount: Int { lock.withLock { startCountStorage } }

  func databaseIdentity() async -> String? { identity }

  func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws {
    lock.withLock {
      startCountStorage += 1
      startCursor = sinceRowID
      handler = onMessage
      failureHandler = onFailure
    }
  }

  func stop() async {
    lock.withLock {
      handler = nil
      failureHandler = nil
    }
  }
  func listChats(limit: Int) async throws -> [IMsgChat] { Array(chats.prefix(limit)) }
  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage] {
    Array((histories[chatID] ?? []).prefix(limit))
  }

  func send(chatID: Int, text: String) async throws {
    if let sendError { throw sendError }
    lock.withLock { sentStorage.append(.init(chatID: chatID, recipient: nil, text: text)) }
  }

  func send(to recipient: String, text: String) async throws {
    if let sendError { throw sendError }
    lock.withLock { sentStorage.append(.init(chatID: nil, recipient: recipient, text: text)) }
  }

  func emit(_ message: IMsgMessage) {
    lock.withLock { handler }?(message)
  }

  func fail(_ error: Error) {
    lock.withLock { failureHandler }?(error)
  }
}

final class EventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [GatewayEvent] = []

  var events: [GatewayEvent] { lock.withLock { storage } }

  func record(_ event: GatewayEvent) {
    lock.withLock { storage.append(event) }
  }
}

actor BlockingXAIClient: XAIResponding {
  private let response: XAIResponse
  private var continuation: CheckedContinuation<Void, Never>?
  private var entered = false

  init(response: XAIResponse) {
    self.response = response
  }

  func respond(
    apiKey: String,
    model: String,
    instructions: String?,
    messages: [XAIMessageInput],
    functionOutput: XAIFunctionOutput?,
    previousResponseID: String?,
    tools: [XAIToolDefinition]
  ) async throws -> XAIResponse {
    entered = true
    await withCheckedContinuation { continuation = $0 }
    return response
  }

  func hasEntered() -> Bool { entered }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

actor BlockingStartMessages: IMsgServicing {
  private var continuation: CheckedContinuation<Void, Error>?
  private var entered = false
  private(set) var stopCount = 0

  func databaseIdentity() async -> String? { "blocking-db" }

  func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws {
    entered = true
    try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func stop() async { stopCount += 1 }
  func listChats(limit: Int) async throws -> [IMsgChat] { [] }
  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage] { [] }
  func send(chatID: Int, text: String) async throws {}
  func send(to recipient: String, text: String) async throws {}
  func hasEntered() -> Bool { entered }

  func releaseStart() {
    continuation?.resume()
    continuation = nil
  }
}

final class MockReminders: RemindersServicing, @unchecked Sendable {
  private let lock = NSLock()
  var status: EKAuthorizationStatus = .fullAccess
  var listValues = [ReminderListRecord(id: "list-1", title: "Reminders")]
  var reminderValues: [ReminderRecord] = []
  private(set) var createdTitles: [String] = []
  private(set) var deletedIDs: [String] = []

  func authorizationStatus() async -> EKAuthorizationStatus { status }
  func requestAccess() async throws -> Bool {
    status = .fullAccess
    return true
  }
  func lists() async throws -> [ReminderListRecord] { listValues }
  func reminders(listName: String?, includeCompleted: Bool, dueBefore: Date?) async throws
    -> [ReminderRecord]
  { reminderValues }

  func create(title: String, notes: String?, listName: String?, dueAt: Date?) async throws
    -> ReminderRecord
  {
    lock.withLock { createdTitles.append(title) }
    return ReminderRecord(
      id: "new-1", title: title, notes: notes, list: listName ?? "Reminders", dueAt: nil,
      isCompleted: false)
  }

  func update(
    id: String, title: String?, notes: String?, dueAt: Date?, clearDueDate: Bool, completed: Bool?
  ) async throws -> ReminderRecord {
    ReminderRecord(
      id: id, title: title ?? "Existing", notes: notes, list: "Reminders", dueAt: nil,
      isCompleted: completed ?? false)
  }

  func delete(id: String) async throws { lock.withLock { deletedIDs.append(id) } }
}

final class ScriptedXAIClient: XAIResponding, @unchecked Sendable {
  struct Call: Equatable {
    let model: String
    let messages: [XAIMessageInput]
    let functionOutput: XAIFunctionOutput?
    let previousResponseID: String?
    let toolNames: [String]
  }

  private let lock = NSLock()
  private var responses: [Result<XAIResponse, Error>]
  private var callsStorage: [Call] = []

  init(_ responses: [Result<XAIResponse, Error>]) { self.responses = responses }
  var calls: [Call] { lock.withLock { callsStorage } }

  func respond(
    apiKey: String,
    model: String,
    instructions: String?,
    messages: [XAIMessageInput],
    functionOutput: XAIFunctionOutput?,
    previousResponseID: String?,
    tools: [XAIToolDefinition]
  ) async throws -> XAIResponse {
    let result: Result<XAIResponse, Error> = lock.withLock {
      callsStorage.append(
        .init(
          model: model,
          messages: messages,
          functionOutput: functionOutput,
          previousResponseID: previousResponseID,
          toolNames: tools.map(\.name)
        ))
      return responses.removeFirst()
    }
    return try result.get()
  }
}

func eventually(
  timeout: TimeInterval = 2,
  condition: @escaping () async -> Bool
) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() { return true }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
  return await condition()
}
