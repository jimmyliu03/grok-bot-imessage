import Foundation
import Security

public enum BridgeTokenError: LocalizedError, Equatable {
  case keychain(OSStatus)
  case randomGeneration(OSStatus)
  case unreadable

  public var errorDescription: String? {
    switch self {
    case .keychain(let status): return "Keychain returned error \(status)."
    case .randomGeneration(let status): return "Could not generate a secure token (\(status))."
    case .unreadable: return "The connector token in Keychain could not be read."
    }
  }
}

public final class BridgeTokenStore: @unchecked Sendable {
  public static let shared = BridgeTokenStore()

  private let service: String
  private let account: String

  public init(service: String = "dev.grokbot.mac", account: String = "mcp-connector-token") {
    self.service = service
    self.account = account
  }

  public func loadOrCreate() throws -> String {
    if let existing = try load() { return existing }
    return try regenerate()
  }

  public func regenerate() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else { throw BridgeTokenError.randomGeneration(status) }
    let token = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    try save(token)
    return token
  }

  public func load() throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw BridgeTokenError.keychain(status) }
    guard let data = result as? Data,
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else { throw BridgeTokenError.unreadable }
    return value
  }

  private func save(_ value: String) throws {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let update = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
    if update == errSecItemNotFound {
      var insert = base
      for (key, value) in attributes { insert[key] = value }
      let status = SecItemAdd(insert as CFDictionary, nil)
      guard status == errSecSuccess else { throw BridgeTokenError.keychain(status) }
    } else if update != errSecSuccess {
      throw BridgeTokenError.keychain(update)
    }
  }
}
