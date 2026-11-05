import Foundation
import Observation
import VitalCourierCore

enum AppTab: Hashable {
  case home
  case history
  case settings
}

@MainActor @Observable
// swiftlint:disable:next type_body_length - the model owns every app-level action; splitting it is a separate refactor
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
  let foregroundEntry: ForegroundEntry
  let tipJar: TipJarModel
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
  /// Days with a pending mark for an enabled type. Separate from `snapshot`, which is nil during the first sync.
  var pendingDayCount = 0
  /// Runs started by a Settings change (Cycle tracking) that are still in flight, so Home shows the running state during a backfill.
  private(set) var trackedRunCount = 0
  /// `requestAppOpenRun` was called while an app-open run was in flight (the phone locked and unlocked during a first sync). The run goes once more when this one finishes.
  private(set) var appOpenRequestedDuringRun = false
  var maintenance: Maintenance = .idle
  var rebuildError: String?
  var clearError: String?
  var now = Date()
  var selectedTab: AppTab = .home
  var cycleTrackingEnabled: Bool
  /// The formats Settings shows as on (Format setting, spec).
  var exportFormats: Set<ExportFormat>

  init(environment: AppEnvironment) {
    self.environment = environment
    history = HistoryModel(environment: environment)
    sleepSources = SleepSourceModel(environment: environment)
    tipJar = TipJarModel(settings: environment.settings)
    cycleTrackingEnabled = environment.settings.cycleTrackingEnabled
    exportFormats = environment.settings.exportFormats
    foregroundEntry = ForegroundEntry(
      authorizationRequestStatus: {
        try await environment.health.readAuthorizationRequestStatus(for: environment.enabledTypes)
      },
      requestAuthorization: { try await environment.health.requestReadAuthorization(for: environment.enabledTypes) },
      recordError: { errorText in Task.detached { environment.recordSetupError(errorText) } }
    )
    sleepSources.onSaved = { [weak self] in self?.requestAppOpenRun() }
    foregroundEntry.requestAppOpenRun = { [weak self] in self?.requestAppOpenRun() }
    foregroundEntry.typesWereAsked = {
      environment.settings.recordHealthTypesAskedAbout(environment.enabledTypes)
      ObserverRegistration.update(environment: environment)
    }
  }

  /// A run the user can see: app open, Rebuild all, Clear local copy or a tracked Settings change.
  var isRunActive: Bool {
    isAppOpenRunActive || maintenance != .idle || trackedRunCount > 0
  }

  var homeSummary: HomeSummary {
    HomeSummary.resolve(
      HomeInputs(
        folder: folderState,
        isRunActive: isRunActive,
        awaitingReread: awaitingReread,
        latestRun: snapshot?.latestRun,
        lastSuccessfulReadAt: snapshot?.lastSuccessfulReadAt,
        dailyValuesFailureStreakStart: snapshot?.dailyValuesFailureStreakStart,
        now: now,
        pendingProtectionFailure: pendingProtectionFailure,
        latestAppEvent: snapshot?.latestAppEvent,
        hasStoredHealthValue: snapshot?.hasStoredHealthValue ?? true,
        pendingDayCount: pendingDayCount
      ))
  }

  var enabledTypes: [HealthType] {
    HealthType.enabledTypes(cycleTrackingEnabled: cycleTrackingEnabled)
  }

  /// The Settings switch (Cycle Tracking Spec). On: ask Health for the two types, watch them, then an app-open run imports all their history the app may read (a type with no anchor reads from the start). Off: drop their pending marks and stop watching; files, samples and cycle rows stay.
  func setCycleTracking(_ isOn: Bool) {
    guard isOn != cycleTrackingEnabled else { return }
    cycleTrackingEnabled = isOn
    environment.setCycleTrackingEnabled(isOn)
    let environment = self.environment
    Task {
      if isOn {
        do {
          try await environment.health.requestReadAuthorization(for: environment.enabledTypes)
          environment.settings.recordHealthTypesAskedAbout(environment.enabledTypes)
        } catch {
          let errorText = "cycle tracking authorization: \(error)"
          await Task.detached { environment.recordSetupError(errorText) }.value
        }
        ObserverRegistration.update(environment: environment)
        // Through the coordinator, not `requestAppOpenRun`, which returns early while an app-open run is in flight; the coordinator merges this into the next batch.
        do {
          try await requestTrackedAppOpenRun()
        } catch {
          statusError = String(describing: error)
        }
      } else {
        do {
          try await environment.deleteCycleDirtyMarks()
        } catch {
          statusError = String(describing: error)
        }
        ObserverRegistration.update(environment: environment)
      }
      await refreshStatus()
    }
  }

  /// The Settings toggle for one export format. The last format on can't be turned off. Turning one on asks for a run: the runner finds the format uncovered at its start and marks every stored day for rewrite, so no Health query is needed. Turning one off only stops its files from updating.
  func setExportFormat(_ format: ExportFormat, isOn: Bool) {
    var formats = exportFormats
    if isOn { formats.insert(format) } else { formats.remove(format) }
    guard formats != exportFormats, environment.settings.setExportFormats(formats) else { return }
    exportFormats = formats
    guard isOn else { return }
    Task {
      do {
        try await requestTrackedAppOpenRun()
      } catch {
        statusError = String(describing: error)
      }
    }
  }

  /// An app-open run through the coordinator, counted in `trackedRunCount` while it lasts. Status is refreshed before the counter drops, so Home never shows a stale state for a run that just finished.
  private func requestTrackedAppOpenRun() async throws {
    trackedRunCount += 1
    defer { trackedRunCount -= 1 }
    do {
      _ = try await environment.request(.appOpen)
    } catch {
      await refreshStatus()
      throw error
    }
    await refreshStatus()
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
        // Asks Health about new types before the app-open run, and only on a foreground launch.
        await foregroundEntry.bootReachedReady()
      }
    }
  }

  func sceneActivityChanged(isActive: Bool) {
    foregroundEntry.sceneActivityChanged(isActive: isActive)
  }

  func sceneBecameActive() {
    guard phase == .ready else { return }
    now = Date()
    let environment = self.environment
    Task {
      folderState = await Task.detached { environment.refreshFolderRecordingLoss() }.value
    }
    Task { await foregroundEntry.sceneBecameActive() }
  }

  func sceneEnteredBackground() {
    guard phase == .ready else { return }
    BackgroundRefresh.submitNextRequest(environment: environment)
  }

  /// Opening the app requests the app-open run; a second one never starts while one is in flight (design §3). A request made during a run is remembered and runs once more after it, without Home leaving the running state in between.
  func requestAppOpenRun() {
    guard phase == .ready else { return }
    guard !isAppOpenRunActive else {
      appOpenRequestedDuringRun = true
      return
    }
    isAppOpenRunActive = true
    let environment = self.environment
    Task {
      repeat {
        repeat {
          appOpenRequestedDuringRun = false
          do {
            _ = try await environment.request(.appOpen)
          } catch {
            statusError = String(describing: error)
          }
        } while appOpenRequestedDuringRun
        // Refresh while the flag is still up, so Home never shows a stale state. A request that lands during this await sends us round again.
        await refreshStatus()
      } while appOpenRequestedDuringRun
      // No suspension point between the last flag check and this drop, so no request can be lost.
      isAppOpenRunActive = false
    }
  }

  /// Re-reads how many days are still pending, for Home's "N days left".
  func refreshPendingDays() async {
    let environment = self.environment
    let types = enabledTypes
    do {
      pendingDayCount = try await Task.detached { try environment.readyStore().pendingDayCount(types: types) }.value
    } catch {
      statusError = String(describing: error)
    }
  }

  /// Loads the snapshot, the pending protection failure and the pending count in one detached task and assigns them together or not at all, so Home never renders a mix of new and old.
  func refreshStatus() async {
    let environment = self.environment
    let types = enabledTypes
    let statusResult = await Task.detached {
      Result {
        let store = try environment.readyStore()
        return (
          try store.statusSnapshot(), store.pendingProtectionFailures().first, try store.pendingDayCount(types: types)
        )
      }
    }.value
    switch statusResult {
    case .success(let (newSnapshot, pendingFailure, newPendingDayCount)):
      snapshot = newSnapshot
      pendingProtectionFailure = pendingFailure
      pendingDayCount = newPendingDayCount
      statusError = nil
    case .failure(let error):
      statusError = String(describing: error)
    }
    folderState = environment.folderAccess.state
    awaitingReread = environment.settings.awaitingRereadAfterClear
    now = Date()
    if history.hasLoadedOnce { await history.reload() }
  }

  /// Asks to read only; no build writes to Apple Health. Records the base types as asked before setup completes and starts the observer.
  func requestHealthAuthorization() async throws {
    try await environment.health.requestReadAuthorization()
    environment.settings.recordHealthTypesAskedAbout(HealthType.baseTypes)
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
    foregroundEntry.setupCompleted()
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
      // Refresh while `maintenance` still holds the running state, then drop it with no suspension in between.
      await refreshStatus()
      maintenance = .idle
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
        await refreshStatus()
        // No suspension point between these two, so `isRunActive` has no gap; `requestAppOpenRun` sets its flag before it first suspends.
        maintenance = .idle
        requestAppOpenRun()
      } catch {
        maintenance = .idle
        clearError = String(describing: error)
      }
    }
  }
}
