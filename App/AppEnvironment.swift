import Foundation
import Synchronization
import UIKit
import VitalCourierCore
import VitalCourierHealthKit

extension Notification.Name {
    /// Posted after every run, whatever its trigger, so open screens re-read their status.
    static let vitalCourierRunFinished = Notification.Name("app.vitalcourier.runFinished")
}

enum StoreState: Sendable {
    case ready(store: LocalStore, coordinator: TriggerCoordinator)
    case blocked(errorText: String)
}

enum AppEnvironmentError: LocalizedError {
    case storeBlocked(String)

    var errorDescription: String? {
        switch self {
        case .storeBlocked(let errorText): "Vital Courier couldn’t open its local data. \(errorText)"
        }
    }
}

/// The one shared container. Built on first use: in `didFinishLaunching` (background launches for HealthKit and `BGAppRefreshTask` never build a scene) or when the App Intent runs.
final class AppEnvironment: Sendable {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let folderAccess: FolderAccess
    let health: HealthKitSource
    private let storeState: Mutex<StoreState>
    private let recordedSetupErrors = Mutex<[String]>([])
    /// Setup errors not yet saved to run history (store blocked, or the save failed). Saved by `drainPendingSetupErrors()`.
    private let pendingSetupErrorsForHistory = Mutex<[String]>([])
    private let observersStarted = Mutex(false)

    init() {
        let settings = AppSettings(storage: StandardUserDefaultsStorage())
        let folderAccess = FolderAccess(settings: settings)
        let health = HealthKitSource { await MainActor.run { UIApplication.shared.isProtectedDataAvailable } }
        self.settings = settings
        self.folderAccess = folderAccess
        self.health = health
        storeState = Mutex(Self.openStore(health: health, folderAccess: folderAccess))
        drainPendingProtectionFailures()
    }

    static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "LocalStore", directoryHint: .isDirectory)
    }

    static func openStore(health: HealthKitSource, folderAccess: FolderAccess) -> StoreState {
        do {
            let store = try LocalStore.open(directory: storeDirectory)
            let runner = ExportRunner(store: store, health: health, destination: { folderAccess.destination() })
            return .ready(store: store, coordinator: TriggerCoordinator(runner: runner))
        } catch {
            // Never delete or recreate the database as recovery (spec, Error handling: migration fails).
            return .blocked(errorText: String(describing: error))
        }
    }

    var storeStateNow: StoreState {
        storeState.withLock { $0 }
    }

    @discardableResult
    func retryOpeningStore() -> StoreState {
        let reopened = Self.openStore(health: health, folderAccess: folderAccess)
        storeState.withLock { $0 = reopened }
        drainPendingProtectionFailures()
        return reopened
    }

    func readyStore() throws -> LocalStore {
        switch storeStateNow {
        case .ready(let store, _): return store
        case .blocked(let errorText): throw AppEnvironmentError.storeBlocked(errorText)
        }
    }

    /// Every trigger goes through here. With a blocked store, `onReadCommitted` runs at once (an observer completion handler must never be held) and the call throws.
    func request(_ trigger: Trigger, onReadCommitted: @escaping @Sendable () -> Void = {}) async throws -> RunOutcome {
        let store: LocalStore
        let coordinator: TriggerCoordinator
        switch storeStateNow {
        case .ready(let readyStore, let readyCoordinator):
            store = readyStore
            coordinator = readyCoordinator
        case .blocked(let errorText):
            onReadCommitted()
            throw AppEnvironmentError.storeBlocked(errorText)
        }
        let outcome = try await coordinator.request(trigger, onReadCommitted: onReadCommitted)
        // `LocalStore` protects its files after every write (Task 3A). A failure after the run's own last write is not in the run record yet: save it to run history now.
        recordProtectionFailures(in: store)
        if outcome.readOutcome == .read {
            settings.awaitingRereadAfterClear = false
        }
        NotificationCenter.default.post(name: .vitalCourierRunFinished, object: nil)
        return outcome
    }

    /// Settings "Clear local copy": waits until no run is active, then clears (design §5). The reread flag is set in the same step, so a run that starts right after can clear it.
    func clearLocalCopy() async throws {
        let store: LocalStore
        let coordinator: TriggerCoordinator
        switch storeStateNow {
        case .ready(let readyStore, let readyCoordinator):
            store = readyStore
            coordinator = readyCoordinator
        case .blocked(let errorText):
            throw AppEnvironmentError.storeBlocked(errorText)
        }
        let settings = self.settings
        try await coordinator.exclusive {
            // `clearLocalCopy` protects the files after its write (Task 3A). A failure is saved to run history here, inside the exclusive block, before any run can start.
            try store.clearLocalCopy()
            settings.awaitingRereadAfterClear = true
            self.recordProtectionFailures(in: store)
        }
    }

    /// Saves failures queued by an earlier launch (Task 3A) as soon as the store opens. A failure to save the row leaves them queued: Home shows them until a row holds them.
    private func drainPendingProtectionFailures() {
        guard case .ready(let store, _) = storeStateNow else { return }
        recordProtectionFailures(in: store)
        drainPendingSetupErrors(in: store)
    }

    /// Saves the queued setup errors as one "App event" row. A failed save puts them back in the queue and records nothing new, so a failing store cannot start a retry loop.
    private func drainPendingSetupErrors(in store: LocalStore) {
        let queuedTexts = pendingSetupErrorsForHistory.withLock { queue in
            defer { queue.removeAll() }
            return queue
        }
        guard !queuedTexts.isEmpty else { return }
        do {
            try store.recordAppEvent(errors: queuedTexts, at: Date())
        } catch {
            pendingSetupErrorsForHistory.withLock { $0.insert(contentsOf: queuedTexts, at: 0) }
        }
    }

    /// Saves pending file-protection failures to run history, so Home and History show them (Task 3A). Only a failure to save the row is left for Diagnostics.
    func recordProtectionFailures(in store: LocalStore) {
        do {
            try store.recordProtectionFailuresInHistory(at: Date())
        } catch {
            recordSetupError("saving a file protection failure to run history: \(error)", savingToHistory: false)
        }
    }

    /// An observer callback waited the whole budget without a committed read and was acknowledged anyway. Saved as a run-history row (an "App event" row, shown as an attention row in History), so it is visible, not only counted.
    func recordObserverAcknowledgementTimeout(type: HealthType) {
        let errorText = "\(RunRecord.observerAcknowledgementErrorPrefix)\(type.rawValue) read had not committed after \(ObserverRegistration.acknowledgementBudgetSeconds) s; acknowledged anyway"
        do {
            try readyStore().recordAppEvent(errors: [errorText], at: Date())
        } catch {
            recordSetupError("\(errorText) (not saved to run history: \(error))", savingToHistory: false)
        }
    }

    /// Failures that have no run to be recorded in (observer and background-delivery registration, a folder that failed to save). Kept for Settings → Diagnostics and saved as an "App event" row in run history. With the store blocked or the save failing, the text waits in a queue that the store open and retry drain. Callers whose own failure was a failed history save pass `savingToHistory: false`: the text is only queued, never saved at once.
    func recordSetupError(_ errorText: String, savingToHistory: Bool = true) {
        recordedSetupErrors.withLock { $0.append(errorText) }
        guard savingToHistory else {
            pendingSetupErrorsForHistory.withLock { $0.append(errorText) }
            return
        }
        do {
            try readyStore().recordAppEvent(errors: [errorText], at: Date())
        } catch {
            pendingSetupErrorsForHistory.withLock { $0.append(errorText) }
        }
    }

    var setupErrors: [String] {
        recordedSetupErrors.withLock { $0 }
    }

    /// Refreshes the folder, and saves the error to run history only when the folder turns lost, so every app open on a still-lost folder adds no row.
    func refreshFolderRecordingLoss() -> FolderState {
        let wasLost: Bool
        if case .lost = folderAccess.state { wasLost = true } else { wasLost = false }
        let refreshed = folderAccess.refresh()
        if case .lost(let errorText) = refreshed, !wasLost {
            recordSetupError("folder lost: \(errorText)")
        }
        return refreshed
    }

    /// True the first time only.
    func markObserversStarted() -> Bool {
        observersStarted.withLock { started in
            defer { started = true }
            return !started
        }
    }
}
