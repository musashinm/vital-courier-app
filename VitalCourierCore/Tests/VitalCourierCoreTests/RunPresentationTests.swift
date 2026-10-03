import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct RunPresentationTests {
    func run(_ readOutcome: ReadOutcome, written: Int = 0, failed: Int = 0, pending: Int = 0, errors: [String] = [], trigger: Trigger = .appOpen) -> RunRecord {
        RunRecord(startedAt: date("2026-10-03T11:16:00Z"), trigger: trigger.rawValue, readOutcome: readOutcome.rawValue, daysWritten: written, daysFailed: failed, daysPending: pending, errors: errors, id: 1)
    }

    @Test func errorStringsTheCoreWritesAreClassified() {
        #expect(RunErrorKind(error: "no folder picked") == .noFolder)
        #expect(RunErrorKind(error: #"json steps 2026-10: bookmarkUnresolvable("folder no longer exists: /x")"#) == .folderLost)
        #expect(RunErrorKind(error: #"note 2026-10-01: writeFailed(path: "Vital Courier/daily/2026-10-01.md", reason: "Não há espaço suficiente. [NSCocoaErrorDomain 640]")"#) == .storageFull)
        #expect(RunErrorKind(error: #"readme: writeFailed(path: "Vital Courier/README.md", reason: "The file couldn’t be saved because there isn’t enough space.")"#) == .storageFull)
        #expect(RunErrorKind(error: "read: anchorDidNotAdvance(steps)") == .read)
        #expect(RunErrorKind(error: "verify steps: boom") == .read)
        #expect(RunErrorKind(error: "verify: boom") == .read)
        #expect(RunErrorKind(error: "observer acknowledgement: steps read had not committed after 30 s; acknowledged anyway") == .read)
        #expect(RunErrorKind(error: "file protection: ProtectionFailed()") == .other)
        #expect(RunErrorKind(error: "daily values steps 2026-10-01: boom") == .dailyValues)
        #expect(RunErrorKind(error: "daily values: boom") == .dailyValues)
        #expect(RunErrorKind(error: "clear 2026-10-01: boom") == .other)
        #expect(RunErrorKind(error: "rebuild: boom") == .other)
        #expect(RunErrorKind(error: "run history: boom") == .other)
    }

    @Test func rowOutcomesFollowTheDesignTable() {
        #expect(RunRowOutcome(run: run(.read)) == .success)
        #expect(RunRowOutcome(run: run(.read, written: 3)) == .success)
        #expect(RunRowOutcome(run: run(.skippedLocked, written: 2)) == .locked)
        #expect(RunRowOutcome(run: run(.notRequested, trigger: .appIntent)) == .notRequested)
        #expect(RunRowOutcome(run: run(.failed, errors: ["read: x"])) == .attention)
        #expect(RunRowOutcome(run: run(.read, errors: ["daily values steps 2026-10-01: x"])) == .attention)
        #expect(RunRowOutcome(run: run(.read, failed: 2, errors: ["json steps 2026-10: x"])) == .exportError)
        #expect(RunRowOutcome(run: run(.notRequested, errors: ["observer acknowledgement: steps read had not committed after 30 s; acknowledged anyway"])) == .attention)
        #expect(RunRowOutcome(run: run(.notRequested, errors: ["file protection: ProtectionFailed()"])) == .exportError)
        #expect(RunRowOutcome(run: run(.skippedLocked, errors: ["no folder picked"])) == .exportError)
        #expect(RunRowOutcome(run: run(.read, errors: ["daily values: x", "clear 2026-10-01: y"])) == .exportError)
    }

    @Test func rowSymbolsAreShapeDistinct() {
        #expect(RunRowOutcome.success.symbolName == "checkmark.circle.fill")
        #expect(RunRowOutcome.locked.symbolName == "lock.fill")
        #expect(RunRowOutcome.notRequested.symbolName == "minus.circle")
        #expect(RunRowOutcome.attention.symbolName == "exclamationmark.triangle.fill")
        #expect(RunRowOutcome.exportError.symbolName == "xmark.octagon.fill")
    }

    @Test func recoveryFollowsTheRunDetailTable() {
        let lost = FolderState.lost(errorText: "bookmarkUnresolvable(\"gone\")")
        let valid = FolderState.valid(displayPath: "iCloud Drive/Health")
        #expect(RunRecovery(run: run(.read, failed: 1, errors: [#"json steps 2026-10: bookmarkUnresolvable("gone")"#]), folder: lost) == .pickFolderAgain)
        #expect(RunRecovery(run: run(.read, errors: ["no folder picked"]), folder: .none) == .pickFolder)
        #expect(RunRecovery(run: run(.read, errors: ["no folder picked"]), folder: valid) == .retryNextRun)
        #expect(RunRecovery(run: run(.read, failed: 1, errors: ["note 2026-10-01: writeFailed(path: \"x\", reason: \"full [NSCocoaErrorDomain 640]\")"]), folder: valid) == .freeUpSpace)
        #expect(RunRecovery(run: run(.failed, errors: ["read: x"]), folder: valid) == .retryNextRun)
        #expect(RunRecovery(run: run(.skippedLocked), folder: valid) == .none)
        #expect(RunRecovery(run: run(.read, written: 2), folder: valid) == .none)
    }

    @Test func labelsMapTheStoredNamesExactly() {
        #expect(RunLabels.trigger("observerWake") == "Observer wake")
        #expect(RunLabels.trigger("appOpen") == "App open")
        #expect(RunLabels.trigger("backgroundRefresh") == "Background refresh")
        #expect(RunLabels.trigger("appIntent") == "Export now")
        #expect(RunLabels.trigger("rebuildAll") == "Rebuild all")
        #expect(RunLabels.trigger(RunRecord.appEventTrigger) == "App event")
        #expect(RunLabels.trigger("somethingNew") == "somethingNew")
        #expect(RunLabels.readOutcome("read") == "Read")
        #expect(RunLabels.readOutcome("skipped: locked") == "Skipped: locked")
        #expect(RunLabels.readOutcome("not requested") == "Not requested")
        #expect(RunLabels.readOutcome("failed") == "Failed")
    }

    @Test func dayCountsShowPendingOnlyWhenNonzero() {
        #expect(RunLabels.dayCounts(run(.read, written: 3)) == "3 written · 0 failed")
        #expect(RunLabels.dayCounts(run(.read, written: 1, failed: 1, pending: 2)) == "1 written · 1 failed · 2 pending")
        #expect(RunLabels.days(1) == "1 day")
        #expect(RunLabels.days(2) == "2 days")
    }

    @Test func theExportNowDialogSummarisesTheOutcome() {
        #expect(RunLabels.exportNowDialog(RunOutcome(readOutcome: .notRequested, daysWritten: 3, daysFailed: 0, daysPending: 0, errors: [])) == "3 days written, 0 failed.")
        #expect(RunLabels.exportNowDialog(RunOutcome(readOutcome: .notRequested, daysWritten: 1, daysFailed: 1, daysPending: 2, errors: ["json steps 2026-10: x", "note 2026-10-01: y"])) == "1 day written, 1 failed, 2 pending. json steps 2026-10: x")
    }
}
