import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct LocalStoreStatusTests {
    func run(_ start: String, _ readOutcome: ReadOutcome, errors: [String] = []) -> RunRecord {
        RunRecord(startedAt: date(start), trigger: Trigger.appOpen.rawValue, readOutcome: readOutcome.rawValue, daysWritten: 0, daysFailed: 0, daysPending: 0, errors: errors)
    }

    @Test func runsPageByCursorNewestFirst() throws {
        let store = try LocalStore.inMemory()
        for hour in 10...14 { try store.appendRun(run("2026-10-01T\(hour):00:00Z", .read)) }

        let first = try store.runs(before: nil, limit: 2)
        let second = try store.runs(before: first.last, limit: 2)
        let third = try store.runs(before: second.last, limit: 2)
        let fourth = try store.runs(before: third.last, limit: 2)

        #expect(first.map(\.startedAt) == [date("2026-10-01T14:00:00Z"), date("2026-10-01T13:00:00Z")])
        #expect(first.map(\.id) == [5, 4])
        #expect(second.map(\.startedAt) == [date("2026-10-01T12:00:00Z"), date("2026-10-01T11:00:00Z")])
        #expect(third.map(\.startedAt) == [date("2026-10-01T10:00:00Z")])
        #expect(fourth.isEmpty)
    }

    @Test func runsWithTheSameStartAreNeitherSkippedNorRepeated() throws {
        let store = try LocalStore.inMemory()
        try store.appendRun(run("2026-10-01T10:00:00Z", .read))
        try store.appendRun(run("2026-10-01T10:00:00Z", .skippedLocked))

        let first = try store.runs(before: nil, limit: 1)
        let second = try store.runs(before: first.last, limit: 1)
        let third = try store.runs(before: second.last, limit: 1)

        #expect(first.map(\.id) == [2])
        #expect(second.map(\.id) == [1])
        #expect(third.isEmpty)
    }

    @Test func aCursorWithoutAnIDIsRejected() throws {
        let store = try LocalStore.inMemory()

        #expect(throws: LocalStoreError.invalidCursor) {
            try store.runs(before: run("2026-10-01T10:00:00Z", .read), limit: 1)
        }
    }

    @Test func lastSuccessfulReadIgnoresLockedAndFailedRuns() throws {
        let store = try LocalStore.inMemory()
        #expect(try store.lastSuccessfulReadAt() == nil)
        try store.appendRun(run("2026-10-01T10:00:00Z", .read))
        try store.appendRun(run("2026-10-01T11:00:00Z", .skippedLocked))
        try store.appendRun(run("2026-10-01T12:00:00Z", .failed, errors: ["read: x"]))
        try store.appendRun(run("2026-10-01T13:00:00Z", .notRequested))

        #expect(try store.lastSuccessfulReadAt() == date("2026-10-01T10:00:00Z"))
    }

    @Test func latestDailyValueDayIsPerType() throws {
        let store = try LocalStore.inMemory()
        try store.saveDailyValue(DailyValue(value: 100), type: .steps, day: day("2026-09-28"))
        try store.saveDailyValue(DailyValue(value: 200), type: .steps, day: day("2026-10-01"))
        try store.saveDailyValue(DailyValue(value: 7.5, source: "Apple Watch"), type: .sleep, day: day("2026-09-30"))

        #expect(try store.latestDailyValueDays() == [.steps: day("2026-10-01"), .sleep: day("2026-09-30")])
    }

    @Test func theDailyValuesStreakStartsAtTheOldestUnbrokenFailure() throws {
        let store = try LocalStore.inMemory()
        #expect(try store.dailyValuesFailureStreakStart() == nil)
        try store.appendRun(run("2026-10-01T10:00:00Z", .read))
        try store.appendRun(run("2026-10-01T11:00:00Z", .read, errors: ["daily values steps 2026-10-01: boom"]))
        // A locked run neither extends nor ends the streak.
        try store.appendRun(run("2026-10-01T12:00:00Z", .skippedLocked))
        // A failed read still ran the daily-values step, so it counts.
        try store.appendRun(run("2026-10-01T13:00:00Z", .failed, errors: ["read: x", "daily values: y"]))

        #expect(try store.dailyValuesFailureStreakStart() == date("2026-10-01T11:00:00Z"))
    }

    @Test func aCleanReadableRunEndsTheStreak() throws {
        let store = try LocalStore.inMemory()
        try store.appendRun(run("2026-10-01T11:00:00Z", .read, errors: ["daily values steps 2026-10-01: boom"]))
        try store.appendRun(run("2026-10-01T12:00:00Z", .read, errors: ["json steps 2026-10: other"]))

        #expect(try store.dailyValuesFailureStreakStart() == nil)
    }

    @Test func sleepSourceNamesAreDistinctAndSortedIgnoringCase() throws {
        let store = try LocalStore.inMemory()
        let sleep = [
            makeSample(type: .sleep, start: "2026-09-30T02:00:00Z", end: "2026-09-30T03:00:00Z", value: .category("asleepCore"), source: "oura"),
            makeSample(type: .sleep, start: "2026-09-30T03:00:00Z", end: "2026-09-30T04:00:00Z", value: .category("asleepCore"), source: "Apple Watch"),
            makeSample(type: .sleep, start: "2026-09-30T04:00:00Z", end: "2026-09-30T05:00:00Z", value: .category("asleepCore"), source: "iPhone"),
            makeSample(type: .sleep, start: "2026-09-30T05:00:00Z", end: "2026-09-30T06:00:00Z", value: .category("asleepCore"), source: "oura"),
        ]
        try store.applyChanges(HealthChanges(added: sleep), for: .sleep, fallbackTimeZone: saoPaulo)
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-30T12:00:00Z", source: "Zepp")]), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try store.sleepSourceNames() == ["Apple Watch", "iPhone", "oura"])
    }

    @Test func theSnapshotCombinesEveryQuery() throws {
        let store = try LocalStore.inMemory()
        try store.appendRun(run("2026-10-01T10:00:00Z", .read))
        try store.appendRun(run("2026-10-01T11:00:00Z", .read, errors: ["daily values steps 2026-10-01: boom"]))
        try store.saveDailyValue(DailyValue(value: 7.5, source: "Apple Watch"), type: .sleep, day: day("2026-09-30"))

        let snapshot = try store.statusSnapshot()

        #expect(snapshot.latestRun?.id == 2)
        #expect(snapshot.lastSuccessfulReadAt == date("2026-10-01T11:00:00Z"))
        #expect(snapshot.dailyValuesFailureStreakStart == date("2026-10-01T11:00:00Z"))
        #expect(snapshot.latestDailyValueDays == [.sleep: day("2026-09-30")])
        #expect(snapshot.latestSleepSource == "Apple Watch")
    }

    @Test func theSnapshotHasTheLatestFlowAndSpottingDays() throws {
        let store = try LocalStore.inMemory()
        let empty = try store.statusSnapshot()
        #expect(empty.latestFlowDay == nil)
        #expect(empty.latestFlow == nil)
        #expect(empty.latestSpottingDay == nil)

        try store.saveCycleDay(.spotting(true), day: day("2026-10-08"))
        try store.saveCycleDay(.flow("heavy", periodStart: true), day: day("2026-10-10"))
        // A later day with spotting only must not replace the latest flow day.
        try store.saveCycleDay(.spotting(true), day: day("2026-10-12"))
        // A later flow that was cleared again leaves no row.
        try store.saveCycleDay(.flow("light", periodStart: false), day: day("2026-10-13"))
        try store.saveCycleDay(.flow(nil, periodStart: false), day: day("2026-10-13"))

        let snapshot = try store.statusSnapshot()
        #expect(snapshot.latestFlowDay == day("2026-10-10"))
        #expect(snapshot.latestFlow == "heavy")
        #expect(snapshot.latestSpottingDay == day("2026-10-12"))
    }
}
