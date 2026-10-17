import Foundation
import Synchronization

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
        static let healthTypesAskedAbout = "healthTypesAskedAbout"
        static let hasTipped = "hasTipped"
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

    /// Set after the first verified tip, never cleared by the app.
    public var hasTipped: Bool {
        get { string(forKey: Key.hasTipped) == "1" }
        nonmutating set { setString(newValue ? "1" : nil, forKey: Key.hasTipped) }
    }

    /// The types Health has been asked to read, so the observer never watches a type whose authorization isn't determined (Exercise Minutes Spec, Launch observer). Stored as a JSON array of raw values; values a later version wrote are ignored.
    public var healthTypesAskedAbout: Set<HealthType> {
        guard let data = storage.data(forKey: Key.healthTypesAskedAbout) else { return Self.typesAskedAboutBeforeThisSetting }
        do {
            return Set(try JSONDecoder().decode([String].self, from: data).compactMap(HealthType.init(rawValue:)))
        } catch {
            return Self.typesAskedAboutBeforeThisSetting
        }
    }

    /// Adds `types` to the asked set. A type is never removed: Health doesn't forget it was asked either. The read, union and write hold one lock, so two recordings can't drop each other's types.
    public func recordHealthTypesAskedAbout(_ types: some Sequence<HealthType>) {
        Self.healthTypesAskedAboutLock.withLock { _ in
            let asked = healthTypesAskedAbout.union(types)
            do {
                storage.set(try JSONEncoder().encode(asked.map(\.rawValue).sorted()), forKey: Key.healthTypesAskedAbout)
            } catch {
                pendingSetupErrors.append("health types asked about could not be encoded: \(error)")
            }
        }
    }

    /// What 0.2.0 and earlier asked for at onboarding. Never the cycle types: 0.2.0 turns the switch on before asking and keeps it on if the request throws, so the switch proves nothing. Written out, not `HealthType.baseTypes`, which grows with later types.
    static let typesAskedAboutBeforeThisSetting: Set<HealthType> = [.steps, .restingHeartRate, .sleep, .weight]

    private static let healthTypesAskedAboutLock = Mutex(())

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
