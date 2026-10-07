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

    @Test func aPortugueseDiskFullErrorIsClassifiedByItsCode() {
        let portugueseDiskFull = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [NSLocalizedDescriptionKey: "Não há espaço suficiente."])
        let saved = "note 2026-10-01: " + String(describing: ExportFolderError.writeFailed(path: "Vital Courier/daily/2026-10-01.md", reason: BookmarkedFolder.describe(portugueseDiskFull)))
        #expect(saved.contains("[NSCocoaErrorDomain 640]"))
        #expect(RunErrorKind(error: saved) == .storageFull)
    }
}
