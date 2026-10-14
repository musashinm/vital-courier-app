import Foundation

/// The app's own small state (design iOS App v2, §5 and §6). Health data never goes here; it stays in the backup-excluded `LocalStore`.
public struct AppSettings: Sendable {
    enum Key {
        static let folderBookmark = "folderBookmark"
        static let folderDisplayPath = "folderDisplayPath"
        static let folderLostError = "folderLostError"
        static let setupCompletedAt = "setupCompletedAt"
        static let awaitingRereadAfterClear = "awaitingRereadAfterClear"
        static let pendingSetupErrors = "pendingSetupErrors"
        static let cycleTrackingEnabled = "cycleTrackingEnabled"
    }

    let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage) {
        self.storage = storage
    }

    public var folderBookmark: Data? {
        get { storage.data(forKey: Key.folderBookmark) }
        nonmutating set { storage.set(newValue, forKey: Key.folderBookmark) }
    }

    public var folderDisplayPath: String? {
        get { string(forKey: Key.folderDisplayPath) }
        nonmutating set { setString(newValue, forKey: Key.folderDisplayPath) }
    }

    /// The last error that made the folder unusable; nil while it works.
    public var folderLostError: String? {
        get { string(forKey: Key.folderLostError) }
        nonmutating set { setString(newValue, forKey: Key.folderLostError) }
    }

    public var setupCompletedAt: Date? {
        get { string(forKey: Key.setupCompletedAt).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }
        nonmutating set { setString(newValue.map { String($0.timeIntervalSince1970) }, forKey: Key.setupCompletedAt) }
    }

    /// Set after Clear local copy succeeds; cleared by the next run whose read outcome is `read`.
    public var awaitingRereadAfterClear: Bool {
        get { string(forKey: Key.awaitingRereadAfterClear) == "1" }
        nonmutating set { setString(newValue ? "1" : nil, forKey: Key.awaitingRereadAfterClear) }
    }

    /// The Settings switch for menstrual flow and spotting (Cycle Tracking Spec). Off by default.
    public var cycleTrackingEnabled: Bool {
        get { string(forKey: Key.cycleTrackingEnabled) == "1" }
        nonmutating set { setString(newValue ? "1" : nil, forKey: Key.cycleTrackingEnabled) }
    }

    /// Setup errors not yet saved to run history, kept outside `LocalStore` so a process exit does not lose them. Stored as a JSON array; stored data that cannot be decoded is returned as one visible entry, never dropped.
    public var pendingSetupErrors: [String] {
        get {
            guard let data = storage.data(forKey: Key.pendingSetupErrors) else { return [] }
            do {
                return try JSONDecoder().decode([String].self, from: data)
            } catch {
                return ["pending setup errors could not be decoded (\(error)): \(String(decoding: data, as: UTF8.self))"]
            }
        }
        nonmutating set {
            if newValue.isEmpty {
                storage.set(nil, forKey: Key.pendingSetupErrors)
                return
            }
            do {
                storage.set(try JSONEncoder().encode(newValue), forKey: Key.pendingSetupErrors)
            } catch {
                storage.set(Data("pending setup errors could not be encoded (\(error))".utf8), forKey: Key.pendingSetupErrors)
            }
        }
    }

    private func string(forKey key: String) -> String? {
        storage.data(forKey: key).map { String(decoding: $0, as: UTF8.self) }
    }

    private func setString(_ value: String?, forKey key: String) {
        storage.set(value.map { Data($0.utf8) }, forKey: key)
    }
}
