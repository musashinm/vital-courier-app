import Foundation

public struct HomeInputs: Sendable {
  public var folder: FolderState
  /// An app-open run, Rebuild all or Clear local copy is in progress.
  public var isRunActive: Bool
  public var awaitingReread: Bool
  public var latestRun: RunRecord?
  public var lastSuccessfulReadAt: Date?
  public var dailyValuesFailureStreakStart: Date?
  public var now: Date
  /// The oldest file-protection failure still waiting in `LocalStore`'s durable queue (Task 3A), so Home shows it before any history row does.
  public var pendingProtectionFailure: String?
  /// The newest history row when it is an App event row (`StoreStatusSnapshot.latestAppEvent`, Task 3A). It is never `latestRun`; Home reads it only to keep showing a protection failure that a saved App event row holds.
  public var latestAppEvent: RunRecord?
  /// The local store currently holds at least one health value, for any type (`StoreStatusSnapshot.hasStoredHealthValue`).
  public var hasStoredHealthValue: Bool
  /// Days with a pending mark for an enabled type (`LocalStore.pendingDayCount(types:)`).
  public var pendingDayCount: Int

  public init(
    folder: FolderState, isRunActive: Bool, awaitingReread: Bool, latestRun: RunRecord?, lastSuccessfulReadAt: Date?,
    dailyValuesFailureStreakStart: Date?, now: Date, pendingProtectionFailure: String? = nil,
    latestAppEvent: RunRecord? = nil, hasStoredHealthValue: Bool = true,
    pendingDayCount: Int = 0
  ) {
    self.folder = folder
    self.isRunActive = isRunActive
    self.awaitingReread = awaitingReread
    self.latestRun = latestRun
    self.lastSuccessfulReadAt = lastSuccessfulReadAt
    self.dailyValuesFailureStreakStart = dailyValuesFailureStreakStart
    self.now = now
    self.pendingProtectionFailure = pendingProtectionFailure
    self.latestAppEvent = latestAppEvent
    self.hasStoredHealthValue = hasStoredHealthValue
    self.pendingDayCount = pendingDayCount
  }
}

public enum HomeSummaryAction: Equatable, Sendable {
  case none
  case runDetails
  case pickFolder
  case pickFolderAgain
  case viewRecentRuns
  case reviewAccess
}

/// The Home export summary (design iOS App v2, §3). The migration blocker is not a case: it replaces the whole root.
public enum HomeSummary: Equatable, Sendable {
  case folderLost(errorText: String)
  case noFolder
  case running(lastCompleted: Date?, daysLeft: Int)
  case awaitingReread
  case protectionFailurePending(errorText: String)
  case protectionFailure(run: RunRecord)
  case writeFailure(run: RunRecord)
  case readOverdue
  case dailyValuesOverdue
  case noHealthDataYet
  case daysUpdated(run: RunRecord)
  case exportPaused(daysLeft: Int)
  case upToDate(run: RunRecord)
  case waitingForFirstExport

  /// At this many pending days or more, the running state says how many are left; below it, a normal run stays quiet.
  public static let catchUpDayThreshold = 7

  public static let overdueInterval: TimeInterval = 24 * 60 * 60

  /// Design §3 priority: folder lost, no folder, active run, waiting to reread, write failure, overdue read, overdue daily values, export paused with days left, a completed read with no stored health data, success, never run. This plan adds two cases between waiting to reread and write failure: a file-protection failure still queued and not yet in a history row, then one recorded in the latest run (Task 3A).
  public static func resolve(_ inputs: HomeInputs) -> HomeSummary {
    if case .lost(let errorText) = inputs.folder { return .folderLost(errorText: errorText) }
    if inputs.folder == .none { return .noFolder }
    if inputs.isRunActive {
      return .running(lastCompleted: inputs.latestRun?.startedAt, daysLeft: inputs.pendingDayCount)
    }
    if inputs.awaitingReread { return .awaitingReread }
    if let failure = protectionFailure(inputs) { return failure }
    if let run = inputs.latestRun, run.daysFailed > 0 { return .writeFailure(run: run) }
    // Never read yet: wait for the first export instead of warning right away (design §6).
    guard let lastRead = inputs.lastSuccessfulReadAt, let run = inputs.latestRun else { return .waitingForFirstExport }
    if inputs.now.timeIntervalSince(lastRead) >= overdueInterval { return .readOverdue }
    if let streakStart = inputs.dailyValuesFailureStreakStart,
      inputs.now.timeIntervalSince(streakStart) >= overdueInterval
    {
      return .dailyValuesOverdue
    }
    // A finished run that left days pending never reads as success, whether or not it wrote some.
    if inputs.pendingDayCount > 0 { return .exportPaused(daysLeft: inputs.pendingDayCount) }
    if !inputs.hasStoredHealthValue { return .noHealthDataYet }
    return run.daysWritten > 0 ? .daysUpdated(run: run) : .upToDate(run: run)
  }

  /// A file-protection failure to show: the queued one first, then one saved in an App event row, then one in the latest run.
  private static func protectionFailure(_ inputs: HomeInputs) -> HomeSummary? {
    if let pending = inputs.pendingProtectionFailure { return .protectionFailurePending(errorText: pending) }
    // An App event row holding a protection failure is not `latestRun`, so it is checked first; the snapshot only sets it while it is the newest row.
    if let event = inputs.latestAppEvent,
      event.errors.contains(where: { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) })
    {
      return .protectionFailure(run: event)
    }
    if let run = inputs.latestRun, run.errors.contains(where: { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) }) {
      return .protectionFailure(run: run)
    }
    return nil
  }
}

/// One Health data row (design §3): recency of stored data, never a health interpretation or a permission claim.
public enum TypeRecency: Equatable, Sendable {
  case updated(DayKey)
  case silentForAWeek
  /// No daily value yet and setup is less than seven days old. "No data yet" is this plan's copy; the design has no row for it.
  case noDataYet

  public static let silentDays = 7

  public static func resolve(latestDay: DayKey?, setupDay: DayKey?, today: DayKey) -> TypeRecency {
    if let latestDay {
      return today >= latestDay.adding(days: silentDays) ? .silentForAWeek : .updated(latestDay)
    }
    if let setupDay, today >= setupDay.adding(days: silentDays) { return .silentForAWeek }
    return .noDataYet
  }
}
