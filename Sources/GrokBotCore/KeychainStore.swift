import Foundation
import Security

public protocol APIKeyProviding: Sendable {
  func apiKey() throws -> String
}

public enum APIKeyError: LocalizedError, Equatable {
  case missing
  case keychain(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .missing:
      return "Add an xAI API key before starting Grok Bot."
    case .keychain(let status):
      return "Keychain returned error \(status)."
    }
  }
}

public final class KeychainAPIKeyStore: APIKeyProviding, @unchecked Sendable {
  public static let shared = KeychainAPIKeyStore()

  private let service: String
  private let account: String

  public init(service: String = "dev.grokbot.mac", account: String = "xai-api-key") {
    self.service = service
    self.account = account
  }

  public func apiKey() throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { throw APIKeyError.missing }
    guard status == errSecSuccess else { throw APIKeyError.keychain(status) }
    guard let data = result as? Data,
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else {
      throw APIKeyError.missing
    }
    return value
  }

  public func hasAPIKey() -> Bool { (try? apiKey()) != nil }

  public func save(_ value: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      try delete()
      return
    }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(trimmed.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insert = base
      attributes.forEach { insert[$0.key] = $0.value }
      let insertStatus = SecItemAdd(insert as CFDictionary, nil)
      guard insertStatus == errSecSuccess else { throw APIKeyError.keychain(insertStatus) }
    } else if status != errSecSuccess {
      throw APIKeyError.keychain(status)
    }
  }

  public func delete() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw APIKeyError.keychain(status)
    }
  }
}

public struct StaticAPIKeyProvider: APIKeyProviding {
  private let value: String
  public init(_ value: String) { self.value = value }
  public func apiKey() throws -> String { value }
}
