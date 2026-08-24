import Foundation

public enum IMsgError: LocalizedError, Equatable {
  case notInstalled
  case notRunning
  case processFailed(String)
  case rpc(code: Int?, message: String)
  case malformedResponse

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      return "imsg is not installed. Install it with Homebrew to connect Messages."
    case .notRunning:
      return "The iMessage bridge is not running."
    case .processFailed(let message):
      return "imsg stopped: \(message)"
    case .rpc(_, let message):
      return message
    case .malformedResponse:
      return "imsg returned an unreadable response."
    }
  }
}

public protocol IMsgServicing: Sendable {
  func databaseIdentity() async -> String?
  func start(sinceRowID: Int?, onMessage: @escaping @Sendable (IMsgMessage) -> Void) async throws
  func stop() async
  func listChats(limit: Int) async throws -> [IMsgChat]
  func history(chatID: Int, limit: Int) async throws -> [IMsgMessage]
  func send(chatID: Int, text: String) async throws
  func send(to recipient: String, text: String) async throws
}

public enum IMsgLocator {
  public static func locate(explicitPath: String? = nil) -> URL? {
    let manager = FileManager.default
    let candidates = [explicitPath, "/opt/homebrew/bin/imsg", "/usr/local/bin/imsg"]
      .compactMap { $0 }
    if let path = candidates.first(where: { manager.isExecutableFile(atPath: $0) }) {
      return URL(fileURLWithPath: path)
    }

    let environmentPaths =
      ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
    for directory in environmentPaths {
      let path = URL(fileURLWithPath: directory).appendingPathComponent("imsg").path
      if manager.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
    }
    return nil
  }
}

public final class IMsgRPCService: IMsgServicing, @unchecked Sendable {
  private let explicitPath: String?
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

  public init(explicitPath: String? = nil) {
    self.explicitPath = explicitPath
  }

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
    onMessage: @escaping @Sendable (IMsgMessage) -> Void
  ) async throws {
    if lock.withLock({ process?.isRunning == true }) { return }
    guard let binaryURL = IMsgLocator.locate(explicitPath: explicitPath) else {
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
      self?.handleTermination(status: process.terminationStatus)
    }

    lock.withLock {
      self.process = child
      self.input = stdinPipe.fileHandleForWriting
      self.output = stdoutPipe.fileHandleForReading
      self.errorOutput = stderrPipe.fileHandleForReading
      self.messageHandler = onMessage
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
        throw IMsgError.rpc(code: nil, message: message)
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
          return value
        }
    snapshot.2?.readabilityHandler = nil
    snapshot.3?.readabilityHandler = nil
    try? snapshot.1?.close()
    if snapshot.0?.isRunning == true { snapshot.0?.terminate() }
    snapshot.4.forEach { $0(.failure(IMsgError.notRunning)) }
  }

  public func listChats(limit: Int = 20) async throws -> [IMsgChat] {
    let result = try await request(
      method: "chats.list", params: ["limit": .number(Double(max(1, min(limit, 100))))])
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
        "transport": .string("auto"),
      ])
  }

  public func send(to recipient: String, text: String) async throws {
    _ = try await request(
      method: "send",
      params: [
        "to": .string(recipient),
        "text": .string(text),
        "service": .string("auto"),
        "transport": .string("auto"),
      ])
  }

  private func request(method: String, params: [String: JSONValue]) async throws -> JSONValue {
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
        try handle?.write(contentsOf: data)
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
        callback?(
          .failure(
            IMsgError.rpc(
              code: error.int("code"), message: error.string("message") ?? "imsg request failed.")))
      } else if let result = object["result"] {
        callback?(.success(result))
      } else {
        callback?(.failure(IMsgError.malformedResponse))
      }
      return
    }
    guard object.string("method") == "message",
      let messageValue = object["params"]?.objectValue?["message"],
      let message = try? decode(IMsgMessage.self, from: messageValue)
    else { return }
    lock.withLock { messageHandler }?(message)
  }

  private func handleTermination(status: Int32) {
    let stderr = lock.withLock { String(data: errorBuffer, encoding: .utf8) ?? "exit \(status)" }
    let callbacks = lock.withLock {
      let values = Array(pending.values)
      pending.removeAll()
      process = nil
      input = nil
      return values
    }
    callbacks.forEach {
      $0(.failure(IMsgError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))))
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
}

public enum IMsgDiagnostics {
  public static func status(explicitPath: String? = nil) async throws -> String {
    guard let binary = IMsgLocator.locate(explicitPath: explicitPath) else {
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
