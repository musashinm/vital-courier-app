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

    public init(folder: FolderState, isRunActive: Bool, awaitingReread: Bool, latestRun: RunRecord?, lastSuccessfulReadAt: Date?, dailyValuesFailureStreakStart: Date?, now: Date, pendingProtectionFailure: String? = nil, latestAppEvent: RunRecord? = nil) {
        self.folder = folder
        self.isRunActive = isRunActive
        self.awaitingReread = awaitingReread
        self.latestRun = latestRun
        self.lastSuccessfulReadAt = lastSuccessfulReadAt
        self.dailyValuesFailureStreakStart = dailyValuesFailureStreakStart
        self.now = now
        self.pendingProtectionFailure = pendingProtectionFailure
        self.latestAppEvent = latestAppEvent
    }
}

public enum HomeSummaryAction: Equatable, Sendable {
    case none
    case runDetails
    case pickFolder
    case pickFolderAgain
    case viewRecentRuns
}

public struct HomeSummaryText: Equatable, Sendable {
    public var symbolName: String
    public var title: String
    public var detail: String?
    /// The full saved error, shown monospaced below the summary.
    public var errorText: String?
    public var showsMoreErrorsNote: Bool
    public var action: HomeSummaryAction

    public init(symbolName: String, title: String, detail: String?, errorText: String?, showsMoreErrorsNote: Bool, action: HomeSummaryAction) {
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.errorText = errorText
        self.showsMoreErrorsNote = showsMoreErrorsNote
        self.action = action
    }
}

/// The Home export summary (design iOS App v2, §3). The migration blocker is not a case: it replaces the whole root.
public enum HomeSummary: Equatable, Sendable {
    case folderLost(errorText: String)
    case noFolder
    case running(lastCompleted: Date?)
    case awaitingReread
    case protectionFailurePending(errorText: String)
    case protectionFailure(run: RunRecord)
    case writeFailure(run: RunRecord)
    case readOverdue
    case dailyValuesOverdue
    case daysUpdated(run: RunRecord)
    case upToDate(run: RunRecord)
    case waitingForFirstExport

    public static let overdueInterval: TimeInterval = 24 * 60 * 60

    /// Design §3 priority: folder lost, no folder, active run, waiting to reread, write failure, overdue read, overdue daily values, success, never run. This plan adds two cases between waiting to reread and write failure: a file-protection failure still queued and not yet in a history row, then one recorded in the latest run (Task 3A).
    public static func resolve(_ inputs: HomeInputs) -> HomeSummary {
        if case .lost(let errorText) = inputs.folder { return .folderLost(errorText: errorText) }
        if inputs.folder == .none { return .noFolder }
        if inputs.isRunActive { return .running(lastCompleted: inputs.latestRun?.startedAt) }
        if inputs.awaitingReread { return .awaitingReread }
        if let pending = inputs.pendingProtectionFailure { return .protectionFailurePending(errorText: pending) }
        // An App event row holding a protection failure is not `latestRun`, so it is checked first; the snapshot only sets it while it is the newest row.
        if let event = inputs.latestAppEvent, event.errors.contains(where: { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) }) { return .protectionFailure(run: event) }
        if let run = inputs.latestRun, run.errors.contains(where: { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) }) { return .protectionFailure(run: run) }
        if let run = inputs.latestRun, run.daysFailed > 0 { return .writeFailure(run: run) }
        // Never read yet: wait for the first export instead of warning right away (design §6).
        guard let lastRead = inputs.lastSuccessfulReadAt, let run = inputs.latestRun else { return .waitingForFirstExport }
        if inputs.now.timeIntervalSince(lastRead) >= overdueInterval { return .readOverdue }
        if let streakStart = inputs.dailyValuesFailureStreakStart, inputs.now.timeIntervalSince(streakStart) >= overdueInterval {
            return .dailyValuesOverdue
        }
        return run.daysWritten > 0 ? .daysUpdated(run: run) : .upToDate(run: run)
    }

    public func text(formatter: StatusDateFormatter, now: Date) -> HomeSummaryText {
        switch self {
        case .folderLost(let errorText):
            HomeSummaryText(symbolName: "folder.badge.minus", title: "Folder lost, pick it again", detail: nil, errorText: errorText, showsMoreErrorsNote: false, action: .pickFolderAgain)
        case .noFolder:
            HomeSummaryText(symbolName: "folder.badge.questionmark", title: "Pick a folder", detail: "Health data can be read locally, but files need a destination.", errorText: nil, showsMoreErrorsNote: false, action: .pickFolder)
        case .running(let lastCompleted):
            HomeSummaryText(symbolName: "arrow.triangle.2.circlepath", title: "Checking for updates…", detail: lastCompleted.map { "Last completed \(formatter.moment($0, now: now))." }, errorText: nil, showsMoreErrorsNote: false, action: .none)
        case .awaitingReread:
            HomeSummaryText(symbolName: "arrow.clockwise.circle", title: "Waiting to reread health data", detail: "Keep this iPhone unlocked and open Vital Courier. Your exported files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .none)
        case .protectionFailurePending(let errorText):
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: "Saving it to History failed. It is saved the next time the app can write.", errorText: RunRecord.fileProtectionErrorPrefix + errorText, showsMoreErrorsNote: false, action: .none)
        case .protectionFailure(let run):
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: nil, errorText: run.errors.first { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) }, showsMoreErrorsNote: run.errors.count > 1, action: .runDetails)
        case .writeFailure(let run):
            HomeSummaryText(symbolName: "xmark.octagon.fill", title: "\(RunLabels.days(run.daysFailed)) failed", detail: nil, errorText: run.errors.first, showsMoreErrorsNote: run.errors.count > 1, action: .runDetails)
        case .readOverdue:
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Health data hasn’t been read in 24 hours", detail: "Unlock this iPhone and open Vital Courier. Saved files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns)
        case .dailyValuesOverdue:
            HomeSummaryText(symbolName: "exclamationmark.arrow.triangle.2.circlepath", title: "Daily summaries haven’t refreshed in 24 hours", detail: "Unlock this iPhone and open Vital Courier to try again.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns)
        case .daysUpdated(let run):
            HomeSummaryText(symbolName: "checkmark.circle.fill", title: "\(RunLabels.days(run.daysWritten)) updated", detail: "\(StatusDateFormatter.capitalizedFirst(formatter.moment(run.startedAt, now: now))) · \(RunLabels.trigger(run.trigger))", errorText: nil, showsMoreErrorsNote: false, action: .runDetails)
        case .upToDate(let run):
            HomeSummaryText(symbolName: "checkmark.circle.fill", title: "Up to date", detail: "Checked \(formatter.moment(run.startedAt, now: now)) · \(RunLabels.trigger(run.trigger))", errorText: nil, showsMoreErrorsNote: false, action: .runDetails)
        case .waitingForFirstExport:
            HomeSummaryText(symbolName: "clock.badge.questionmark", title: "Waiting for the first export", detail: "Keep your iPhone unlocked while Vital Courier reads the four data types.", errorText: nil, showsMoreErrorsNote: false, action: .none)
        }
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

    public func valueText(formatter: StatusDateFormatter, today: DayKey, source: String?) -> String {
        switch self {
        case .updated(let day):
            let updated = "Updated \(formatter.day(day, today: today))"
            return source.map { "\(updated) · \($0)" } ?? updated
        case .silentForAWeek:
            return "No data received in 7 days"
        case .noDataYet:
            return "No data yet"
        }
    }
}
