import Foundation

public protocol GatewayStateStoring: Sendable {
  func load() throws -> PersistedGatewayState
  func save(_ state: PersistedGatewayState) throws
}

public final class JSONGatewayStateStore: GatewayStateStoring, @unchecked Sendable {
  public let fileURL: URL
  private let lock = NSLock()

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      self.fileURL = base.appendingPathComponent("GrokBot", isDirectory: true)
        .appendingPathComponent("gateway-state.json")
    }
  }

  public func load() throws -> PersistedGatewayState {
    lock.lock()
    defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return PersistedGatewayState()
    }
    return try JSONDecoder.grokBot.decode(
      PersistedGatewayState.self, from: Data(contentsOf: fileURL))
  }

  public func save(_ state: PersistedGatewayState) throws {
    lock.lock()
    defer { lock.unlock() }
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder.grokBot.encode(state)
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}

public final class InMemoryGatewayStateStore: GatewayStateStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var state: PersistedGatewayState

  public init(state: PersistedGatewayState = .init()) { self.state = state }

  public func load() throws -> PersistedGatewayState {
    lock.withLock { state }
  }

  public func save(_ state: PersistedGatewayState) throws {
    lock.withLock { self.state = state }
  }
}

extension JSONEncoder {
  fileprivate static var grokBot: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var grokBot: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
