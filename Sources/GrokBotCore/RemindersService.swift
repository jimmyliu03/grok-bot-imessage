import EventKit
import Foundation

public struct ReminderListRecord: Codable, Equatable, Sendable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct ReminderRecord: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let notes: String?
  public let list: String
  public let dueAt: String?
  public let isCompleted: Bool

  public init(
    id: String, title: String, notes: String?, list: String, dueAt: String?, isCompleted: Bool
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.list = list
    self.dueAt = dueAt
    self.isCompleted = isCompleted
  }
}

public enum RemindersError: LocalizedError, Equatable {
  case accessDenied
  case listNotFound(String)
  case reminderNotFound(String)
  case invalidDate(String)

  public var errorDescription: String? {
    switch self {
    case .accessDenied: return "Reminders access is not granted."
    case .listNotFound(let value): return "No reminder list named “\(value)” was found."
    case .reminderNotFound(let value): return "No reminder with ID \(value) was found."
    case .invalidDate(let value): return "“\(value)” is not a valid ISO 8601 date."
    }
  }
}

public protocol RemindersServicing: Sendable {
  func authorizationStatus() async -> EKAuthorizationStatus
  func requestAccess() async throws -> Bool
  func lists() async throws -> [ReminderListRecord]
  func reminders(listName: String?, includeCompleted: Bool, dueBefore: Date?) async throws
    -> [ReminderRecord]
  func create(title: String, notes: String?, listName: String?, dueAt: Date?) async throws
    -> ReminderRecord
  func update(
    id: String, title: String?, notes: String?, dueAt: Date?, clearDueDate: Bool, completed: Bool?
  ) async throws -> ReminderRecord
  func delete(id: String) async throws
}

@MainActor
public final class EventKitRemindersService: RemindersServicing, @unchecked Sendable {
  public static let shared = EventKitRemindersService()
  private let store: EKEventStore

  public init(store: EKEventStore = EKEventStore()) {
    self.store = store
  }

  public func authorizationStatus() async -> EKAuthorizationStatus {
    EKEventStore.authorizationStatus(for: .reminder)
  }

  public func requestAccess() async throws -> Bool {
    try await store.requestFullAccessToReminders()
  }

  public func lists() async throws -> [ReminderListRecord] {
    try requireAccess()
    return store.calendars(for: .reminder)
      .map { ReminderListRecord(id: $0.calendarIdentifier, title: $0.title) }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  public func reminders(
    listName: String?,
    includeCompleted: Bool,
    dueBefore: Date?
  ) async throws -> [ReminderRecord] {
    try requireAccess()
    let calendars = try calendars(named: listName)
    let predicate = store.predicateForReminders(in: calendars)
    let reminders = await withCheckedContinuation { continuation in
      store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
    }
    return
      reminders
      .filter { includeCompleted || !$0.isCompleted }
      .filter { reminder in
        guard let dueBefore else { return true }
        guard let dueDate = reminder.dueDateComponents?.date else { return false }
        return dueDate <= dueBefore
      }
      .map(record)
      .sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }
  }

  public func create(
    title: String,
    notes: String?,
    listName: String?,
    dueAt: Date?
  ) async throws -> ReminderRecord {
    try requireAccess()
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.notes = notes
    if let listName {
      reminder.calendar = try calendars(named: listName).first
    } else {
      reminder.calendar = store.defaultCalendarForNewReminders()
    }
    guard reminder.calendar != nil else { throw RemindersError.listNotFound("default") }
    reminder.dueDateComponents = dueAt.map(dateComponents)
    try store.save(reminder, commit: true)
    return record(reminder)
  }

  public func update(
    id: String,
    title: String?,
    notes: String?,
    dueAt: Date?,
    clearDueDate: Bool,
    completed: Bool?
  ) async throws -> ReminderRecord {
    try requireAccess()
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindersError.reminderNotFound(id)
    }
    if let title { reminder.title = title }
    if let notes { reminder.notes = notes }
    if clearDueDate { reminder.dueDateComponents = nil }
    if let dueAt { reminder.dueDateComponents = dateComponents(dueAt) }
    if let completed { reminder.isCompleted = completed }
    try store.save(reminder, commit: true)
    return record(reminder)
  }

  public func delete(id: String) async throws {
    try requireAccess()
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindersError.reminderNotFound(id)
    }
    try store.remove(reminder, commit: true)
  }

  private func requireAccess() throws {
    guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
      throw RemindersError.accessDenied
    }
  }

  private func calendars(named name: String?) throws -> [EKCalendar] {
    let values = store.calendars(for: .reminder)
    guard let name, !name.isEmpty else { return values }
    let matches = values.filter { $0.title.caseInsensitiveCompare(name) == .orderedSame }
    guard !matches.isEmpty else { throw RemindersError.listNotFound(name) }
    return matches
  }

  private func dateComponents(_ date: Date) -> DateComponents {
    Calendar.current.dateComponents(in: TimeZone.current, from: date)
  }

  private func record(_ reminder: EKReminder) -> ReminderRecord {
    ReminderRecord(
      id: reminder.calendarItemIdentifier,
      title: reminder.title,
      notes: reminder.notes,
      list: reminder.calendar.title,
      dueAt: reminder.dueDateComponents?.date.map { ISO8601DateFormatter.grokBot.string(from: $0) },
      isCompleted: reminder.isCompleted
    )
  }
}

extension ISO8601DateFormatter {
  static let grokBot: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func grokBotDate(from value: String) -> Date? {
    grokBot.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
