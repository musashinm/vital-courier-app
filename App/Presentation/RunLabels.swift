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

    /// What the Export now App Intent says back to Shortcuts. A resource, so the system resolves it in the request's language. The first error stays as saved (diagnostic text).
    static func exportNowDialog(_ outcome: RunOutcome) -> LocalizedStringResource {
        let errorSuffix = outcome.errors.first.map { " \($0)" } ?? ""
        let written = outcome.daysWritten
        let failed = outcome.daysFailed
        let pending = outcome.daysPending
        // Written and failed counts of 0 have their own keys (Portuguese plural rules put 0 with 1, spec Decision 7), hence the eight cases.
        switch (written == 0, failed == 0, pending > 0) {
        case (true, true, false): return LocalizedStringResource("0 days written, 0 failed.\(errorSuffix)")
        case (true, true, true): return LocalizedStringResource("0 days written, 0 failed, \(pending) pending.\(errorSuffix)")
        case (true, false, false): return LocalizedStringResource("0 days written, \(failed) failed.\(errorSuffix)")
        case (true, false, true): return LocalizedStringResource("0 days written, \(failed) failed, \(pending) pending.\(errorSuffix)")
        case (false, true, false): return LocalizedStringResource("\(written) days written, 0 failed.\(errorSuffix)")
        case (false, true, true): return LocalizedStringResource("\(written) days written, 0 failed, \(pending) pending.\(errorSuffix)")
        case (false, false, false): return LocalizedStringResource("\(written) days written, \(failed) failed.\(errorSuffix)")
        case (false, false, true): return LocalizedStringResource("\(written) days written, \(failed) failed, \(pending) pending.\(errorSuffix)")
        }
    }
}
