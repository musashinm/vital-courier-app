import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct HomeStatusTests {
    let now = date("2026-10-03T11:16:00Z")
    let valid = FolderState.valid(displayPath: "iCloud Drive/Health")

    func run(_ start: String, written: Int = 0, failed: Int = 0, errors: [String] = [], trigger: Trigger = .appOpen) -> RunRecord {
        RunRecord(startedAt: date(start), trigger: trigger.rawValue, readOutcome: ReadOutcome.read.rawValue, daysWritten: written, daysFailed: failed, daysPending: 0, errors: errors, id: 7)
    }

    func inputs(
        folder: FolderState? = nil,
        isRunActive: Bool = false,
        awaitingReread: Bool = false,
        latestRun: RunRecord? = nil,
        lastRead: Date? = nil,
        streakStart: Date? = nil,
        pendingProtection: String? = nil,
        appEvent: RunRecord? = nil
    ) -> HomeInputs {
        HomeInputs(folder: folder ?? valid, isRunActive: isRunActive, awaitingReread: awaitingReread, latestRun: latestRun, lastSuccessfulReadAt: lastRead, dailyValuesFailureStreakStart: streakStart, now: now, pendingProtectionFailure: pendingProtection, latestAppEvent: appEvent)
    }

    @Test func theFolderComesBeforeEverythingElse() {
        let failing = run("2026-10-03T10:00:00Z", failed: 2)
        #expect(HomeSummary.resolve(inputs(folder: .lost(errorText: "gone"), isRunActive: true, latestRun: failing)) == .folderLost(errorText: "gone"))
        #expect(HomeSummary.resolve(inputs(folder: FolderState.none, isRunActive: true, latestRun: failing)) == .noFolder)
    }

    @Test func anActiveRunBeatsTheRereadAndFailures() {
        let latest = run("2026-10-03T00:42:00Z", failed: 2)
        #expect(HomeSummary.resolve(inputs(isRunActive: true, awaitingReread: true, latestRun: latest)) == .running(lastCompleted: latest.startedAt))
        #expect(HomeSummary.resolve(inputs(awaitingReread: true, latestRun: latest)) == .awaitingReread)
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: now)) == .writeFailure(run: latest))
    }

    @Test func aProtectionFailureInTheLatestRunIsShownBeforeWriteFailures() {
        let failing = run("2026-10-03T10:00:00Z", failed: 1, errors: ["note 2026-10-01: x", "file protection: ProtectionFailed()"])
        #expect(HomeSummary.resolve(inputs(latestRun: failing, lastRead: now)) == .protectionFailure(run: failing))
        // A saved App event row holding the failure is not the latest run, but Home still shows it.
        let event = RunRecord(startedAt: date("2026-10-03T11:00:00Z"), trigger: RunRecord.appEventTrigger, readOutcome: ReadOutcome.notRequested.rawValue, daysWritten: 0, daysFailed: 0, daysPending: 0, errors: ["file protection: ProtectionFailed()"], id: 8)
        #expect(HomeSummary.resolve(inputs(latestRun: run("2026-10-03T10:00:00Z", written: 1), lastRead: now, appEvent: event)) == .protectionFailure(run: event))
        #expect(HomeSummary.resolve(inputs(isRunActive: true, latestRun: failing, lastRead: now)) == .running(lastCompleted: failing.startedAt))
        #expect(HomeSummary.resolve(inputs(folder: .lost(errorText: "gone"), latestRun: failing, lastRead: now)) == .folderLost(errorText: "gone"))
    }

    @Test func aQueuedProtectionFailureIsShownUntilAHistoryRowHoldsIt() {
        let healthy = run("2026-10-03T10:00:00Z", written: 1)
        let queued = HomeSummary.resolve(inputs(latestRun: healthy, lastRead: now, pendingProtection: "ProtectionFailed()"))
        #expect(queued == .protectionFailurePending(errorText: "ProtectionFailed()"))
        // Once a row holds it the queue is empty, and the row's own state takes over.
        #expect(HomeSummary.resolve(inputs(latestRun: healthy, lastRead: now)) == .daysUpdated(run: healthy))
        // The folder and an active run still come first.
        #expect(HomeSummary.resolve(inputs(folder: .lost(errorText: "gone"), latestRun: healthy, lastRead: now, pendingProtection: "x")) == .folderLost(errorText: "gone"))
        #expect(HomeSummary.resolve(inputs(isRunActive: true, latestRun: healthy, lastRead: now, pendingProtection: "x")) == .running(lastCompleted: healthy.startedAt))
    }

    @Test func neverHavingReadWaitsForTheFirstExportInsteadOfWarning() {
        #expect(HomeSummary.resolve(inputs()) == .waitingForFirstExport)
        #expect(HomeSummary.resolve(inputs(latestRun: run("2026-10-01T10:00:00Z"))) == .waitingForFirstExport)
    }

    @Test func theReadWarningStartsAtExactly24Hours() {
        let latest = run("2026-10-03T11:00:00Z")
        let justUnder = now.addingTimeInterval(-24 * 60 * 60 + 1)
        let exactly = now.addingTimeInterval(-24 * 60 * 60)
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: justUnder)) == .upToDate(run: latest))
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: exactly)) == .readOverdue)
    }

    @Test func theDailyValuesWarningNeedsAStreakOfAtLeast24Hours() {
        let latest = run("2026-10-03T11:00:00Z")
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: now, streakStart: now.addingTimeInterval(-3600))) == .upToDate(run: latest))
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: now, streakStart: now.addingTimeInterval(-24 * 60 * 60))) == .dailyValuesOverdue)
        // A stale read is reported first.
        #expect(HomeSummary.resolve(inputs(latestRun: latest, lastRead: now.addingTimeInterval(-25 * 60 * 60), streakStart: now.addingTimeInterval(-30 * 60 * 60))) == .readOverdue)
    }

    @Test func successSaysHowManyDaysWereUpdated() {
        let wrote = run("2026-10-03T11:16:00Z", written: 3, trigger: .observerWake)
        #expect(HomeSummary.resolve(inputs(latestRun: wrote, lastRead: now)) == .daysUpdated(run: wrote))
    }

    @Test func aTypeGoesSilentAfterSevenDays() {
        let today = day("2026-10-03")
        #expect(TypeRecency.resolve(latestDay: day("2026-09-27"), setupDay: nil, today: today) == .updated(day("2026-09-27")))
        #expect(TypeRecency.resolve(latestDay: day("2026-09-26"), setupDay: nil, today: today) == .silentForAWeek)
        #expect(TypeRecency.resolve(latestDay: nil, setupDay: day("2026-09-27"), today: today) == .noDataYet)
        #expect(TypeRecency.resolve(latestDay: nil, setupDay: day("2026-09-26"), today: today) == .silentForAWeek)
        #expect(TypeRecency.resolve(latestDay: nil, setupDay: nil, today: today) == .noDataYet)
    }
}
