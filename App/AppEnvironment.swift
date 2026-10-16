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
        case .storeBlocked(let errorText): String(localized: "Vital Courier couldn’t open its local data. \(errorText)")
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
    /// Guards read-modify-write of the durable queue `settings.pendingSetupErrors` (setup errors not yet saved to run history). The Bool is true while one drain is running.
    private let setupErrorQueue = Mutex(false)
    private let observersStarted = Mutex(false)
    private let cycleTrackingTransition = CycleTrackingTransition()

    init() {
        let settings = AppSettings(storage: StandardUserDefaultsStorage())
        let folderAccess = FolderAccess(settings: settings)
        let health = HealthKitSource { await MainActor.run { UIApplication.shared.isProtectedDataAvailable } }
        self.settings = settings
        self.folderAccess = folderAccess
        self.health = health
        storeState = Mutex(Self.openStore(health: health, folderAccess: folderAccess, settings: settings))
        drainPendingProtectionFailures()
    }

    static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "LocalStore", directoryHint: .isDirectory)
    }

    static func openStore(health: HealthKitSource, folderAccess: FolderAccess, settings: AppSettings) -> StoreState {
        do {
            let store = try LocalStore.open(directory: storeDirectory)
            let runner = ExportRunner(
                store: store,
                health: health,
                destination: { folderAccess.destination() },
                enabledTypes: { HealthType.enabledTypes(cycleTrackingEnabled: settings.cycleTrackingEnabled) },
                readableTypes: { HealthType.observedTypes(enabled: HealthType.enabledTypes(cycleTrackingEnabled: settings.cycleTrackingEnabled), askedAbout: settings.healthTypesAskedAbout) }
            )
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
        let reopened = Self.openStore(health: health, folderAccess: folderAccess, settings: settings)
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

    /// The types the app reads, observes, exports and lists right now (Cycle Tracking Spec).
    var enabledTypes: [HealthType] {
        HealthType.enabledTypes(cycleTrackingEnabled: settings.cycleTrackingEnabled)
    }

    /// The only way the app changes the Cycle tracking switch, so it can't land between `deleteCycleDirtyMarks`'s check and its deletion.
    func setCycleTrackingEnabled(_ isEnabled: Bool) {
        cycleTrackingTransition.setEnabled(isEnabled, in: settings)
    }

    /// Cycle tracking turned off: drops pending cycle marks once no run is active, so a run already past its read can't write them after the switch.
    /// The switch is checked again under the transition lock inside the exclusive section: if tracking came back on while this waited, that run's marks stay.
    func deleteCycleDirtyMarks() async throws {
        switch storeStateNow {
        case .ready(let store, let coordinator):
            try await coordinator.exclusive {
                try self.cycleTrackingTransition.deleteMarksIfStillOff(in: store, settings: self.settings)
                self.recordProtectionFailures(in: store)
            }
        case .blocked(let errorText):
            throw AppEnvironmentError.storeBlocked(errorText)
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

    /// Saves the queued setup errors as one "App event" row per round, and removes exactly the saved entries only after the save succeeded (entries appended meanwhile stay and are picked up by the loop). One drain runs at a time. A failed save leaves the queue as it is and records nothing new, so a failing store cannot start a retry loop.
    private func drainPendingSetupErrors(in store: LocalStore) {
        let claimed = setupErrorQueue.withLock { isDraining in
            if isDraining { return false }
            isDraining = true
            return true
        }
        guard claimed else { return }
        while true {
            let snapshot = setupErrorQueue.withLock { isDraining in
                let queued = settings.pendingSetupErrors
                if queued.isEmpty { isDraining = false }
                return queued
            }
            if snapshot.isEmpty { return }
            do {
                try store.recordAppEvent(errors: snapshot, at: Date())
            } catch {
                setupErrorQueue.withLock { $0 = false }
                return
            }
            setupErrorQueue.withLock { _ in
                settings.pendingSetupErrors = Array(settings.pendingSetupErrors.dropFirst(snapshot.count))
            }
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

    /// Failures that have no run to be recorded in (observer and background-delivery registration, a folder that failed to save). Kept in memory for Settings → Diagnostics, and queued durably (outside the store) for run history as an "App event" row. After queueing, a ready store drains the queue at once; otherwise the store open and retry drain it. Callers whose own failure was a failed history save pass `savingToHistory: false`: the text is only queued, with no drain.
    func recordSetupError(_ errorText: String, savingToHistory: Bool = true) {
        recordedSetupErrors.withLock { $0.append(errorText) }
        setupErrorQueue.withLock { _ in
            settings.pendingSetupErrors = settings.pendingSetupErrors + [errorText]
        }
        guard savingToHistory, case .ready(let store, _) = storeStateNow else { return }
        drainPendingSetupErrors(in: store)
    }

    var setupErrors: [String] {
        recordedSetupErrors.withLock { $0 }
    }

    /// Refreshes the folder. Saves the error to run history when the folder turns lost (so every app open on a still-lost folder adds no row), and when the file provider can't be reached, which `FolderAccess` reports once per outage and which leaves the folder valid.
    func refreshFolderRecordingLoss() -> FolderState {
        let wasLost: Bool
        if case .lost = folderAccess.state { wasLost = true } else { wasLost = false }
        let (refreshed, temporaryFailure) = folderAccess.refreshReportingTemporaryFailure()
        if case .lost(let errorText) = refreshed, !wasLost {
            recordSetupError("folder lost: \(errorText)")
        }
        if let temporaryFailure {
            recordSetupError("folder temporarily unavailable: \(temporaryFailure)")
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
