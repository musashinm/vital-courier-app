import Foundation
import VitalCourierCore

/// What the Home summary row shows for a `HomeSummary` (design iOS App v2, §3).
struct HomeSummaryText: Equatable {
    var symbolName: String
    var title: String
    var detail: String?
    /// The full saved error, shown monospaced below the summary.
    var errorText: String?
    var showsMoreErrorsNote: Bool
    var action: HomeSummaryAction
}

extension HomeSummary {
    func text(formatter: StatusDateFormatter, now: Date) -> HomeSummaryText {
        let localization = formatter.localization
        return switch self {
        case .folderLost(let errorText):
            HomeSummaryText(symbolName: "folder.badge.minus", title: localization.string("Folder lost, pick it again"), detail: nil, errorText: errorText, showsMoreErrorsNote: false, action: .pickFolderAgain)
        case .noFolder:
            HomeSummaryText(symbolName: "folder.badge.questionmark", title: localization.string("Pick a folder"), detail: localization.string("Health data can be read locally, but files need a destination."), errorText: nil, showsMoreErrorsNote: false, action: .pickFolder)
        case .running(let lastCompleted):
            HomeSummaryText(symbolName: "arrow.triangle.2.circlepath", title: localization.string("Checking for updates…"), detail: lastCompleted.map { localization.string("Last completed \(formatter.moment($0, now: now)).") }, errorText: nil, showsMoreErrorsNote: false, action: .none)
        case .awaitingReread:
            HomeSummaryText(symbolName: "arrow.clockwise.circle", title: localization.string("Waiting to reread health data"), detail: localization.string("Keep this iPhone unlocked and open Vital Courier. Your exported files remain in place."), errorText: nil, showsMoreErrorsNote: false, action: .none)
        case .protectionFailurePending(let errorText):
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: localization.string("Local data protection failed"), detail: localization.string("Saving it to History failed. It is saved the next time the app can write."), errorText: RunRecord.fileProtectionErrorPrefix + errorText, showsMoreErrorsNote: false, action: .none)
        case .protectionFailure(let run):
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: localization.string("Local data protection failed"), detail: nil, errorText: run.errors.first { $0.hasPrefix(RunRecord.fileProtectionErrorPrefix) }, showsMoreErrorsNote: run.errors.count > 1, action: .runDetails)
        case .writeFailure(let run):
            HomeSummaryText(symbolName: "xmark.octagon.fill", title: RunLabels.daysFailed(run.daysFailed, in: localization), detail: nil, errorText: run.errors.first, showsMoreErrorsNote: run.errors.count > 1, action: .runDetails)
        case .readOverdue:
            HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: localization.string("Health data hasn’t been read in 24 hours"), detail: localization.string("Unlock this iPhone and open Vital Courier. Saved files remain in place."), errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns)
        case .dailyValuesOverdue:
            HomeSummaryText(symbolName: "exclamationmark.arrow.triangle.2.circlepath", title: localization.string("Daily summaries haven’t refreshed in 24 hours"), detail: localization.string("Unlock this iPhone and open Vital Courier to try again."), errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns)
        case .daysUpdated(let run):
            HomeSummaryText(symbolName: "checkmark.circle.fill", title: RunLabels.daysUpdated(run.daysWritten, in: localization), detail: "\(formatter.capitalizedFirst(formatter.moment(run.startedAt, now: now))) · \(RunLabels.trigger(run.trigger, in: localization))", errorText: nil, showsMoreErrorsNote: false, action: .runDetails)
        case .upToDate(let run):
            HomeSummaryText(symbolName: "checkmark.circle.fill", title: localization.string("Up to date"), detail: localization.string("Checked \(formatter.moment(run.startedAt, now: now)) · \(RunLabels.trigger(run.trigger, in: localization))"), errorText: nil, showsMoreErrorsNote: false, action: .runDetails)
        case .waitingForFirstExport:
            HomeSummaryText(symbolName: "clock.badge.questionmark", title: localization.string("Waiting for the first export"), detail: localization.string("Keep your iPhone unlocked while Vital Courier reads the four data types."), errorText: nil, showsMoreErrorsNote: false, action: .none)
        }
    }
}

/// One Health data row's value (design §3): recency of stored data, never a health interpretation or a permission claim.
extension TypeRecency {
    func valueText(formatter: StatusDateFormatter, today: DayKey, source: String?) -> String {
        let localization = formatter.localization
        switch self {
        case .updated(let day):
            let dayText = formatter.day(day, today: today)
            guard let source else { return localization.string("Updated \(dayText)") }
            return localization.string("Updated \(dayText) · \(source)")
        case .silentForAWeek:
            return localization.string("No data received in 7 days")
        case .noDataYet:
            return localization.string("No data yet")
        }
    }
}
