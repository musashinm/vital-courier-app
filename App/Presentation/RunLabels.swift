import Foundation
import VitalCourierCore

enum RunLabels {
    /// Design §4 trigger map, plus "App event" (a history row no run produced). An unknown stored name is shown as saved.
    static func trigger(_ stored: String, in localization: AppLocalization = .system) -> String {
        if stored == RunRecord.appEventTrigger { return localization.string("App event") }
        return switch Trigger(rawValue: stored) {
        case .observerWake: localization.string("Observer wake")
        case .appOpen: localization.string("App open")
        case .backgroundRefresh: localization.string("Background refresh")
        case .appIntent: localization.string("Export now")
        case .rebuildAll: localization.string("Rebuild all")
        case nil: stored
        }
    }

    /// Design §4 read-outcome map.
    static func readOutcome(_ stored: String, in localization: AppLocalization = .system) -> String {
        switch ReadOutcome(rawValue: stored) {
        // "Read" is also the Run detail row label; its own key lets Portuguese say "Lido" here and "Leitura" there.
        case .read: localization.string("readOutcome.read", defaultValue: "Read")
        case .skippedLocked: localization.string("Skipped: locked")
        case .notRequested: localization.string("Not requested")
        case .failed: localization.string("Failed")
        case nil: stored
        }
    }

    /// Counts of 0 have their own key: Portuguese plural rules put 0 with 1 ("0 dia"), spec Decision 7.
    static func daysUpdated(_ count: Int, in localization: AppLocalization = .system) -> String {
        count == 0 ? localization.string("0 days updated") : localization.string("\(count) days updated")
    }

    static func daysFailed(_ count: Int, in localization: AppLocalization = .system) -> String {
        count == 0 ? localization.string("0 days failed") : localization.string("\(count) days failed")
    }

    static func dayCounts(_ run: RunRecord, in localization: AppLocalization = .system) -> String {
        if run.daysPending > 0 {
            return localization.string("\(run.daysWritten) written · \(run.daysFailed) failed · \(run.daysPending) pending")
        }
        return localization.string("\(run.daysWritten) written · \(run.daysFailed) failed")
    }

    /// What the Export now App Intent says back to Shortcuts. English for now; Task 4 of the localization plan makes it a resource.
    static func exportNowDialog(_ outcome: RunOutcome) -> String {
        let daysWritten = outcome.daysWritten == 1 ? "1 day" : "\(outcome.daysWritten) days"
        var text = "\(daysWritten) written, \(outcome.daysFailed) failed"
        if outcome.daysPending > 0 { text += ", \(outcome.daysPending) pending" }
        text += "."
        if let firstError = outcome.errors.first { text += " \(firstError)" }
        return text
    }
}
