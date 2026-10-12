import Foundation
import Observation
import VitalCourierCore

enum AppTab: Hashable {
    case home
    case history
    case settings
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case booting
        case blocked(errorText: String)
        case onboarding
        case ready
    }

    enum Maintenance: Equatable {
        case idle
        case rebuilding
        case clearing
    }

    enum FolderSaveState: Equatable {
        case idle
        case saving
        case saved(displayPath: String)
        case failed(errorText: String)
    }

    static let bootProgressDelay = Duration.milliseconds(300)

    let environment: AppEnvironment
    let history: HistoryModel
    let sleepSources: SleepSourceModel
    var phase: Phase = .booting
    var showsBootProgress = false
    var isRetryingStore = false
    var folderState: FolderState = .none
    var folderSave: FolderSaveState = .idle
    var snapshot: StoreStatusSnapshot?
    /// The oldest file-protection failure still queued (Task 3A); Home shows it until a history row holds it.
    var pendingProtectionFailure: String?
    var statusError: String?
    var awaitingReread = false
    var isAppOpenRunActive = false
    var maintenance: Maintenance = .idle
    var rebuildError: String?
    var clearError: String?
    var now = Date()
    var selectedTab: AppTab = .home

    init(environment: AppEnvironment) {
        self.environment = environment
        history = HistoryModel(environment: environment)
        sleepSources = SleepSourceModel(environment: environment)
        sleepSources.onSaved = { [weak self] in self?.requestAppOpenRun() }
    }

    var homeSummary: HomeSummary {
        HomeSummary.resolve(HomeInputs(
            folder: folderState,
            isRunActive: isAppOpenRunActive || maintenance != .idle,
            awaitingReread: awaitingReread,
            latestRun: snapshot?.latestRun,
            lastSuccessfulReadAt: snapshot?.lastSuccessfulReadAt,
            dailyValuesFailureStreakStart: snapshot?.dailyValuesFailureStreakStart,
            now: now,
            pendingProtectionFailure: pendingProtectionFailure,
            latestAppEvent: snapshot?.latestAppEvent
        ))
    }

    /// Design §1: resolve the store, the folder and setup before choosing the root; show progress only after 300 ms.
    func boot() async {
        let progressGate = Task {
            try? await Task.sleep(for: Self.bootProgressDelay)
            if phase == .booting { showsBootProgress = true }
        }
        let environment = self.environment
        let (storeState, folder) = await Task.detached {
            (environment.storeStateNow, environment.refreshFolderRecordingLoss())
        }.value
        progressGate.cancel()
        showsBootProgress = false
        folderState = folder
        await apply(storeState)
    }

    func retryStore() async {
        isRetryingStore = true
        let environment = self.environment
        let storeState = await Task.detached { environment.retryOpeningStore() }.value
        isRetryingStore = false
        await apply(storeState)
    }

    private func apply(_ storeState: StoreState) async {
        switch storeState {
        case .blocked(let errorText):
            phase = .blocked(errorText: errorText)
        case .ready:
            if environment.settings.setupCompletedAt == nil {
                phase = .onboarding
            } else {
                phase = .ready
                ObserverRegistration.start(environment: environment)
                await refreshStatus()
                requestAppOpenRun()
            }
        }
    }

    func sceneBecameActive() {
        guard phase == .ready else { return }
        now = Date()
        let environment = self.environment
        Task {
            folderState = await Task.detached { environment.refreshFolderRecordingLoss() }.value
        }
        requestAppOpenRun()
    }

    func sceneEnteredBackground() {
        guard phase == .ready else { return }
        BackgroundRefresh.submitNextRequest(environment: environment)
    }

    /// Opening the app requests the app-open run; a second one never starts while one is in flight (design §3).
    func requestAppOpenRun() {
        guard phase == .ready, !isAppOpenRunActive else { return }
        isAppOpenRunActive = true
        let environment = self.environment
        Task {
            do {
                _ = try await environment.request(.appOpen)
            } catch {
                statusError = String(describing: error)
            }
            isAppOpenRunActive = false
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        let environment = self.environment
        do {
            let (newSnapshot, pendingFailure) = try await Task.detached {
                let store = try environment.readyStore()
                return (try store.statusSnapshot(), store.pendingProtectionFailures().first)
            }.value
            snapshot = newSnapshot
            pendingProtectionFailure = pendingFailure
            statusError = nil
        } catch {
            statusError = String(describing: error)
        }
        folderState = environment.folderAccess.state
        awaitingReread = environment.settings.awaitingRereadAfterClear
        now = Date()
        if history.hasLoadedOnce { await history.reload() }
    }

    /// Asks to read only; no build writes to Apple Health.
    func requestHealthAuthorization() async throws {
        try await environment.health.requestReadAuthorization()
    }

    func pickFolder(_ url: URL) {
        folderSave = .saving
        let environment = self.environment
        Task {
            do {
                let state = try await Task.detached { try environment.folderAccess.savePickedFolder(url) }.value
                folderState = state
                if case .valid(let displayPath) = state { folderSave = .saved(displayPath: displayPath) }
                if phase == .ready { requestAppOpenRun() }
            } catch {
                let errorText = String(describing: error)
                folderSave = .failed(errorText: errorText)
                await Task.detached { environment.recordSetupError("folder save: \(errorText)") }.value
            }
        }
    }

    func completeSetup() {
        environment.settings.setupCompletedAt = Date()
        folderSave = .idle
        phase = .ready
        ObserverRegistration.start(environment: environment)
        requestAppOpenRun()
    }

    func rebuildAll() {
        guard maintenance == .idle else { return }
        maintenance = .rebuilding
        rebuildError = nil
        let environment = self.environment
        Task {
            do {
                _ = try await environment.request(.rebuildAll)
            } catch {
                rebuildError = String(describing: error)
            }
            maintenance = .idle
            await refreshStatus()
        }
    }

    func clearLocalCopy() {
        guard maintenance == .idle else { return }
        maintenance = .clearing
        clearError = nil
        let environment = self.environment
        Task {
            do {
                try await environment.clearLocalCopy()
                maintenance = .idle
                await refreshStatus()
                requestAppOpenRun()
            } catch {
                maintenance = .idle
                clearError = String(describing: error)
            }
        }
    }
}
