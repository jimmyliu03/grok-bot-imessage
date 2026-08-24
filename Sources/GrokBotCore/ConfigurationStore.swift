import Foundation

public final class ConfigurationStore: @unchecked Sendable {
  public static let shared = ConfigurationStore()

  private let defaults: UserDefaults
  private let key = "botConfiguration.v1"
  private let lock = NSLock()

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> BotConfiguration {
    lock.withLock {
      guard let data = defaults.data(forKey: key),
        let value = try? JSONDecoder().decode(BotConfiguration.self, from: data)
      else {
        return BotConfiguration()
      }
      return value
    }
  }

  public func save(_ configuration: BotConfiguration) throws {
    try lock.withLock {
      defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }
  }
}
