import Foundation
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite struct RunLabelsTests {
    func run(written: Int = 0, failed: Int = 0, pending: Int = 0) -> RunRecord {
        RunRecord(startedAt: date("2026-10-03T11:16:00Z"), trigger: Trigger.appOpen.rawValue, readOutcome: ReadOutcome.read.rawValue, daysWritten: written, daysFailed: failed, daysPending: pending, errors: [], id: 1)
    }

    @Test func labelsMapTheStoredNamesExactly() {
        #expect(RunLabels.trigger("observerWake", in: .english) == "Observer wake")
        #expect(RunLabels.trigger("appOpen", in: .english) == "App open")
        #expect(RunLabels.trigger("backgroundRefresh", in: .english) == "Background refresh")
        #expect(RunLabels.trigger("appIntent", in: .english) == "Export now")
        #expect(RunLabels.trigger("rebuildAll", in: .english) == "Rebuild all")
        #expect(RunLabels.trigger(RunRecord.appEventTrigger, in: .english) == "App event")
        #expect(RunLabels.trigger("somethingNew", in: .english) == "somethingNew")
        #expect(RunLabels.readOutcome("read", in: .english) == "Read")
        #expect(RunLabels.readOutcome("skipped: locked", in: .english) == "Skipped: locked")
        #expect(RunLabels.readOutcome("not requested", in: .english) == "Not requested")
        #expect(RunLabels.readOutcome("failed", in: .english) == "Failed")
        #expect(RunLabels.readOutcome("somethingNew", in: .english) == "somethingNew")
    }

    @Test func dayCountsShowPendingOnlyWhenNonzero() {
        #expect(RunLabels.dayCounts(run(written: 3), in: .english) == "3 written · 0 failed")
        #expect(RunLabels.dayCounts(run(written: 1, failed: 1, pending: 2), in: .english) == "1 written · 1 failed · 2 pending")
    }

    @Test func zeroCountsUseTheirOwnKey() {
        #expect(RunLabels.daysUpdated(0, in: .english) == "0 days updated")
        #expect(RunLabels.daysUpdated(1, in: .english) == "1 day updated")
        #expect(RunLabels.daysUpdated(2, in: .english) == "2 days updated")
        #expect(RunLabels.daysFailed(0, in: .english) == "0 days failed")
        #expect(RunLabels.daysFailed(1, in: .english) == "1 day failed")
        #expect(RunLabels.daysFailed(2, in: .english) == "2 days failed")
    }

    @Test func theExportNowDialogSummarisesTheOutcome() {
        #expect(RunLabels.exportNowDialog(RunOutcome(readOutcome: .notRequested, daysWritten: 3, daysFailed: 0, daysPending: 0, errors: [])) == "3 days written, 0 failed.")
        #expect(RunLabels.exportNowDialog(RunOutcome(readOutcome: .notRequested, daysWritten: 1, daysFailed: 1, daysPending: 2, errors: ["json steps 2026-10: x", "note 2026-10-01: y"])) == "1 day written, 1 failed, 2 pending. json steps 2026-10: x")
    }
}
