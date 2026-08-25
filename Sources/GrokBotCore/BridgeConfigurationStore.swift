import Foundation

public final class BridgeConfigurationStore: @unchecked Sendable {
  public static let shared = BridgeConfigurationStore()

  private let defaults: UserDefaults
  private let key = "bridgeConfiguration.v1"
  private let lock = NSLock()

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> BridgeConfiguration {
    lock.withLock {
      guard let data = defaults.data(forKey: key),
        let value = try? JSONDecoder().decode(BridgeConfiguration.self, from: data)
      else { return BridgeConfiguration() }
      return value
    }
  }

  public func save(_ configuration: BridgeConfiguration) throws {
    try lock.withLock {
      defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }
  }
}
