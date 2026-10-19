import Foundation
import Synchronization

public protocol KeyValueStorage: Sendable {
  func data(forKey key: String) -> Data?
  func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults.standard`: device-local, never synced to iCloud, readable after first unlock (background runs need it).
public struct StandardUserDefaultsStorage: KeyValueStorage {
  public init() {}

  public func data(forKey key: String) -> Data? {
    UserDefaults.standard.data(forKey: key)
  }

  public func set(_ data: Data?, forKey key: String) {
    if let data {
      UserDefaults.standard.set(data, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

public final class InMemoryStorage: KeyValueStorage {
  private let values = Mutex<[String: Data]>([:])

  public init() {}

  public func data(forKey key: String) -> Data? {
    values.withLock { $0[key] }
  }

  public func set(_ data: Data?, forKey key: String) {
    values.withLock { $0[key] = data }
  }
}
