import Foundation

public enum IMsgError: LocalizedError, Equatable {
  case notInstalled
  case notRunning
  case processFailed(String)
  case rpc(code: Int?, message: String, retrySafe: Bool?, disposition: String?)
  case deliveryBlocked(String)
  case watchTerminated(message: String, resumeAfterRowID: Int?)
  case timedOut(String)
  case malformedResponse

  public var requiresManualDeliveryCheck: Bool {
    switch self {
    case .rpc(let code, _, let retrySafe, _):
      return retrySafe == false || code == -32_001 || code == -32_004
    case .deliveryBlocked:
      return true
    default:
      return false
    }
  }

  public var resumeAfterRowID: Int? {
    guard case .watchTerminated(_, let rowID) = self else { return nil }
    return rowID
  }

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      return "imsg is not installed. Install it with Homebrew to connect Messages."
    case .notRunning:
      return "The iMessage bridge is not running."
    case .processFailed(let message):
      return "imsg stopped: \(message)"
    case .rpc(_, let message, let retrySafe, let disposition):
      guard retrySafe == false else { return message }
      let detail = disposition.map { " (\($0))" } ?? ""
      return "\(message)\(detail). Delivery may have completed; check Messages before restarting."
    case .deliveryBlocked(let message):
      return
        "Message sending is paused after an uncertain delivery: \(message) Restart Grok Bot only after checking Messages."
    case .watchTerminated(let message, _):
      return message
    case .timedOut(let method):
      return "imsg did not answer \(method) within 30 seconds."
    case .malformedResponse:
      return "imsg returned an unreadable response."
    }
  }
}

public protocol IMsgServicing: Sendable {
  func databaseIdentity() async -> String?
  func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws
  func stop() async
  func listChats(limit: Int, unreadOnly: Bool) async throws -> [IMsgChat]
  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage]
  func send(chatID: Int, text: String) async throws
  func send(to recipient: String, text: String, service: String) async throws
}

public enum IMsgLocator {
  public static func locate() -> URL? {
    let manager = FileManager.default
    let candidates = ["/opt/homebrew/bin/imsg", "/usr/local/bin/imsg"]
    let trustedRoots = ["/opt/homebrew/Cellar/imsg/", "/usr/local/Cellar/imsg/"]
    for path in candidates where manager.isExecutableFile(atPath: path) {
      let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      guard trustedRoots.contains(where: { canonical.path.hasPrefix($0) }),
        let attributes = try? manager.attributesOfItem(atPath: canonical.path),
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
        permissions & 0o022 == 0
      else { continue }
      return canonical
    }
    return nil
  }
}

public final class IMsgRPCService: IMsgServicing, @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var errorOutput: FileHandle?
  private var readBuffer = Data()
  private var errorBuffer = Data()
  private var nextID = 1
  private var pending: [String: (Result<JSONValue, Error>) -> Void] = [:]
  private var messageHandler: (@Sendable (IMsgMessage) -> Void)?
  private var failureHandler: (@Sendable (Error) -> Void)?
  private var mutationBlockReason: String?

  public init() {}

  public func databaseIdentity() async -> String? {
    let path = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Messages/chat.db").path
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
      return nil
    }
    let system = (attributes[.systemNumber] as? NSNumber)?.stringValue ?? "?"
    let file = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? "?"
    let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(system):\(file):\(created)"
  }

  deinit {
    process?.terminate()
  }

  public func start(
    sinceRowID: Int?,
    onMessage: @escaping @Sendable (IMsgMessage) -> Void,
    onFailure: @escaping @Sendable (Error) -> Void
  ) async throws {
    if lock.withLock({ process?.isRunning == true }) { return }
    guard let binaryURL = IMsgLocator.locate() else {
      throw IMsgError.notInstalled
    }

    let child = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    child.executableURL = binaryURL
    child.arguments = ["rpc"]
    child.standardInput = stdinPipe
    child.standardOutput = stdoutPipe
    child.standardError = stderrPipe

    stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.consumeStdout(handle.availableData)
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.consumeStderr(handle.availableData)
    }
    child.terminationHandler = { [weak self] process in
      self?.handleTermination(process)
    }

    lock.withLock {
      self.process = child
      self.input = stdinPipe.fileHandleForWriting
      self.output = stdoutPipe.fileHandleForReading
      self.errorOutput = stderrPipe.fileHandleForReading
      self.messageHandler = onMessage
      self.failureHandler = onFailure
      self.mutationBlockReason = nil
      self.readBuffer.removeAll(keepingCapacity: true)
      self.errorBuffer.removeAll(keepingCapacity: true)
    }

    do {
      try child.run()
      let status = try await request(method: "initialize", params: ["protocol_version": .number(1)])
      guard status.objectValue?["database"]?.objectValue?["ready"]?.boolValue == true else {
        let message =
          status.objectValue?["database"]?.objectValue?["error"]?.stringValue
          ?? "Grant Full Disk Access to Grok Bot, then restart it."
        throw IMsgError.rpc(code: nil, message: message, retrySafe: nil, disposition: nil)
      }
      var params: [String: JSONValue] = [
        "attachments": .bool(false),
        "include_reactions": .bool(false),
        "debounce_ms": .number(500),
        "buffer_limit": .number(512),
      ]
      if let sinceRowID { params["since_rowid"] = .number(Double(sinceRowID)) }
      _ = try await request(method: "watch.subscribe", params: params)
    } catch {
      await stop()
      throw error
    }
  }

  public func stop() async {
    let snapshot:
      (Process?, FileHandle?, FileHandle?, FileHandle?, [(Result<JSONValue, Error>) -> Void]) =
        lock.withLock {
          let callbacks = Array(pending.values)
          pending.removeAll()
          let value = (process, input, output, errorOutput, callbacks)
          process = nil
          input = nil
          output = nil
          errorOutput = nil
          messageHandler = nil
          failureHandler = nil
          return value
        }
    snapshot.2?.readabilityHandler = nil
    snapshot.3?.readabilityHandler = nil
    try? snapshot.1?.close()
    if snapshot.0?.isRunning == true { snapshot.0?.terminate() }
    for callback in snapshot.4 { callback(.failure(IMsgError.notRunning)) }
  }

  public func listChats(limit: Int = 20, unreadOnly: Bool = false) async throws -> [IMsgChat] {
    let result = try await request(
      method: "chats.list",
      params: [
        "limit": .number(Double(max(1, min(limit, 100)))),
        "unread_only": .bool(unreadOnly),
      ])
    guard let values = result.objectValue?["chats"]?.arrayValue else {
      throw IMsgError.malformedResponse
    }
    return try values.map { try decode(IMsgChat.self, from: $0) }
  }

  public func history(chatID: Int, limit: Int = 20) async throws -> [IMsgMessage] {
    let result = try await request(
      method: "messages.history",
      params: [
        "chat_id": .number(Double(chatID)),
        "limit": .number(Double(max(1, min(limit, 100)))),
        "attachments": .bool(false),
      ])
    guard let values = result.objectValue?["messages"]?.arrayValue else {
      throw IMsgError.malformedResponse
    }
    return try values.map { try decode(IMsgMessage.self, from: $0) }
  }

  public func send(chatID: Int, text: String) async throws {
    _ = try await request(
      method: "send",
      params: [
        "chat_id": .number(Double(chatID)),
        "text": .string(text),
        "transport": .string("applescript"),
      ])
  }

  public func send(to recipient: String, text: String, service: String = "auto") async throws {
    _ = try await request(
      method: "send",
      params: [
        "to": .string(recipient),
        "text": .string(text),
        "service": .string(service),
        "transport": .string("applescript"),
      ])
  }

  private func request(method: String, params: [String: JSONValue]) async throws -> JSONValue {
    if method == "send", let reason = lock.withLock({ mutationBlockReason }) {
      throw IMsgError.deliveryBlocked(reason)
    }
    guard lock.withLock({ process?.isRunning == true }) else { throw IMsgError.notRunning }
    let id: String = lock.withLock {
      defer { nextID += 1 }
      return String(nextID)
    }
    let envelope: JSONValue = .object([
      "jsonrpc": .string("2.0"),
      "id": .string(id),
      "method": .string(method),
      "params": .object(params),
    ])
    var data = try JSONEncoder().encode(envelope)
    data.append(0x0A)

    return try await withCheckedThrowingContinuation { continuation in
      let callback: (Result<JSONValue, Error>) -> Void = { continuation.resume(with: $0) }
      let handle: FileHandle? = lock.withLock {
        pending[id] = callback
        return input
      }
      do {
        guard let handle else { throw IMsgError.notRunning }
        try handle.write(contentsOf: data)
        Task { [weak self] in
          try? await Task.sleep(for: .seconds(30))
          guard let self else { return }
          let timeoutError: IMsgError
          if method == "send" {
            timeoutError = .rpc(
              code: nil,
              message: "imsg send timed out",
              retrySafe: false,
              disposition: "delivery unknown"
            )
          } else {
            timeoutError = .timedOut(method)
          }
          let callback = self.lock.withLock { () -> ((Result<JSONValue, Error>) -> Void)? in
            let value = self.pending.removeValue(forKey: id)
            if method == "send", value != nil {
              self.mutationBlockReason = timeoutError.localizedDescription
            }
            return value
          }
          callback?(.failure(timeoutError))
        }
      } catch {
        let callback = lock.withLock { pending.removeValue(forKey: id) }
        callback?(.failure(error))
      }
    }
  }

  private func consumeStdout(_ data: Data) {
    guard !data.isEmpty else { return }
    let lines: [Data] = lock.withLock {
      readBuffer.append(data)
      var complete: [Data] = []
      while let newline = readBuffer.firstIndex(of: 0x0A) {
        complete.append(readBuffer.prefix(upTo: newline))
        readBuffer.removeSubrange(...newline)
      }
      return complete
    }
    lines.filter { !$0.isEmpty }.forEach(handleLine)
  }

  private func consumeStderr(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.withLock {
      errorBuffer.append(data)
      if errorBuffer.count > 16_384 { errorBuffer.removeFirst(errorBuffer.count - 16_384) }
    }
  }

  private func handleLine(_ data: Data) {
    guard let envelope = try? JSONDecoder().decode(JSONValue.self, from: data),
      let object = envelope.objectValue
    else { return }
    if let id = object["id"]?.stringValue {
      let callback = lock.withLock { pending.removeValue(forKey: id) }
      if let error = object["error"]?.objectValue {
        let rpcError = Self.decodeRPCError(error)
        if rpcError.requiresManualDeliveryCheck {
          lock.withLock { mutationBlockReason = rpcError.localizedDescription }
        }
        callback?(.failure(rpcError))
      } else if let result = object["result"] {
        callback?(.success(result))
      } else {
        callback?(.failure(IMsgError.malformedResponse))
      }
      return
    }
    if object.string("method") == "watch.overflow" {
      let resumeAfter = object["params"]?.objectValue?.int("resume_after_rowid")
      let suffix = resumeAfter.map { " Resume from row \($0)." } ?? ""
      let error = IMsgError.watchTerminated(
        message:
          "The Messages watch overflowed and stopped.\(suffix) Grok Bot will reconnect safely.",
        resumeAfterRowID: resumeAfter)
      lock.withLock { failureHandler }?(error)
      return
    }
    guard object.string("method") == "message",
      let messageValue = object["params"]?.objectValue?["message"],
      let message = try? decode(IMsgMessage.self, from: messageValue)
    else { return }
    lock.withLock { messageHandler }?(message)
  }

  static func decodeRPCError(_ error: [String: JSONValue]) -> IMsgError {
    let data = error["data"]?.objectValue
    return .rpc(
      code: error.int("code"),
      message: error.string("message") ?? "imsg request failed.",
      retrySafe: data?.bool("retry_safe"),
      disposition: data?.string("disposition")
    )
  }

  private func handleTermination(_ terminatedProcess: Process) {
    let snapshot: (String, [(Result<JSONValue, Error>) -> Void], (@Sendable (Error) -> Void)?)? =
      lock.withLock {
        guard process === terminatedProcess else { return nil }
        let stderr = String(data: errorBuffer, encoding: .utf8) ?? ""
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "exit \(terminatedProcess.terminationStatus)" : detail
        let values = Array(pending.values)
        pending.removeAll()
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        messageHandler = nil
        let failure = failureHandler
        failureHandler = nil
        return (message, values, failure)
      }
    guard let snapshot else { return }
    let error = IMsgError.processFailed(snapshot.0)
    for callback in snapshot.1 { callback(.failure(error)) }
    snapshot.2?(error)
  }

  private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
}

public enum IMsgDiagnostics {
  public static func status() async throws -> String {
    guard let binary = IMsgLocator.locate() else {
      throw IMsgError.notInstalled
    }
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = binary
    let input = Pipe()
    process.arguments = ["rpc"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let probe = Data(
      "{\"jsonrpc\":\"2.0\",\"id\":\"probe\",\"method\":\"initialize\",\"params\":{\"protocol_version\":1}}\n"
        .utf8)
    try input.fileHandleForWriting.write(contentsOf: probe)
    try input.fileHandleForWriting.close()
    let stdout = output.fileHandleForReading.readDataToEndOfFile()
    let stderr = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw IMsgError.processFailed(String(data: stderr, encoding: .utf8) ?? "status failed")
    }
    return String(data: stdout, encoding: .utf8) ?? "Ready"
  }
}
