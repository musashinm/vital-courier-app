import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct ExportRunnerReadTests {
    let now = date("2026-09-30T15:00:00Z")

    func makeRunner(store: LocalStore, health: FakeHealthSource, destination: FakeDestination? = nil) -> ExportRunner {
        let fixedNow = now
        return ExportRunner(store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { saoPaulo })
    }

    @Test func anObserverRunReadsStoresAndComputesDailyValues() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")], newAnchor: Data([7])), for: .steps)
        await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
        let commits = EventLog()

        let outcome = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) { commits.append("committed") }

        #expect(outcome.readOutcome == .read)
        // No folder in this suite, so the write step records its one error; the read side had none.
        #expect(outcome.errors == ["no folder picked"])
        #expect(commits.all == ["committed"])
        #expect(try store.anchor(for: .steps) == Data([7]))
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true)])
        #expect(try store.dailyValues(day: day("2026-09-27")) == [.steps: DailyValue(value: 8412)])
    }

    @Test func theReadCallbackFiresBeforeDailyValuesAreQueried() async throws {
        let store = try LocalStore.inMemory()
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) { log.append("committed") }

        let entries = log.all
        let committed = try #require(entries.firstIndex(of: "committed"))
        let firstStatistic = try #require(entries.firstIndex { $0.hasPrefix("statistic") })
        #expect(committed < firstStatistic)
    }

    @Test func aLockedPhoneSkipsReadingButStillCallsBack() async throws {
        let store = try LocalStore.inMemory()
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        await health.setReadable(false)
        let commits = EventLog()

        let outcome = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) { commits.append("committed") }

        #expect(outcome.readOutcome == .skippedLocked)
        #expect(commits.all == ["committed"])
        #expect(log.all.isEmpty)
    }

    @Test func aRefusedReadCountsAsLocked() async throws {
        let health = FakeHealthSource()
        await health.setRefuseReads(true)
        let outcome = await makeRunner(store: try LocalStore.inMemory(), health: health).run(trigger: .appOpen, options: .forTrigger(.appOpen)) {}
        #expect(outcome.readOutcome == .skippedLocked)
        #expect(outcome.errors.isEmpty)
    }

    @Test func theAppIntentNeverReads() async throws {
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        let outcome = await makeRunner(store: try LocalStore.inMemory(), health: health).run(trigger: .appIntent, options: .forTrigger(.appIntent)) {}
        #expect(outcome.readOutcome == .notRequested)
        #expect(log.all.isEmpty)
    }

    @Test func verifyRemovesRecentSamplesHealthKitDroppedAndLeavesOlderOnes() async throws {
        let store = try LocalStore.inMemory()
        let recent = makeSample(start: "2026-09-25T12:00:00Z")
        let old = makeSample(start: "2026-08-01T12:00:00Z")
        try store.applyChanges(HealthChanges(added: [recent, old]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.clearDirty(type: .steps, day: day("2026-09-25"))
        try store.clearDirty(type: .steps, day: day("2026-08-01"))
        let health = FakeHealthSource()
        await health.setSamples([], for: .steps)

        _ = await makeRunner(store: store, health: health).run(trigger: .appOpen, options: .forTrigger(.appOpen)) {}

        #expect(try store.samples(type: .steps, month: "2026-09").isEmpty)
        #expect(try store.samples(type: .steps, month: "2026-08").map(\.uuid) == [old.uuid])
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-25")])
    }

    @Test func verifyAddsSamplesTheStoreIsMissing() async throws {
        let store = try LocalStore.inMemory()
        let missing = makeSample(start: "2026-09-28T12:00:00Z")
        let health = FakeHealthSource()
        await health.setSamples([missing], for: .steps)

        _ = await makeRunner(store: store, health: health).run(trigger: .appOpen, options: .forTrigger(.appOpen)) {}

        #expect(try store.samples(type: .steps, month: "2026-09").map(\.uuid) == [missing.uuid])
    }

    @Test func aFailedStatisticLeavesTheEntryStaleAndIsRecorded() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)
        await health.failStatistic(for: .steps, day: day("2026-09-27"))

        let outcome = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dirtyEntries().first?.fresh == false)
        // The statistic failure plus the write step's "no folder picked".
        #expect(outcome.errors.count == 2)
        #expect(outcome.errors.contains { $0.hasPrefix("daily values steps") })
    }

    @Test func weightUsesTheLatestSampleOfTheDay() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [
            makeSample(type: .weight, start: "2026-09-27T11:00:00Z", value: .quantity(72.8)),
            makeSample(type: .weight, start: "2026-09-27T21:00:00Z", value: .quantity(72.1)),
        ]), for: .weight)

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dailyValues(day: day("2026-09-27"))[.weight] == DailyValue(value: 72.1))
    }

    @Test func sleepUsesTheAggregatorAndTheUsersPick() async throws {
        let store = try LocalStore.inMemory()
        try store.setSleepSourcePreference("iPhone")
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [
            makeSample(type: .sleep, start: "2026-09-27T02:00:00Z", end: "2026-09-27T09:00:00Z", value: .category("asleepUnspecified"), source: "iPhone", device: "iPhone"),
            makeSample(type: .sleep, start: "2026-09-27T02:30:00Z", end: "2026-09-27T07:30:00Z", value: .category("asleepCore"), source: "Watch", device: "Apple Watch"),
        ]), for: .sleep)

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        let night = try #require(try store.dailyValues(day: day("2026-09-27"))[.sleep])
        #expect(night.source == "iPhone")
        #expect(night.value == 7)
    }

    @Test func aLateSampleForAWrittenDayMarksItDirtyAgain() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.saveDailyValue(DailyValue(value: 10), type: .steps, day: day("2026-09-27"))
        try store.clearDirty(type: .steps, day: day("2026-09-27"))
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T20:00:00Z")]), for: .steps)
        await health.setStatistic(20, for: .steps, day: day("2026-09-27"))

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true)])
        #expect(try store.dailyValues(day: day("2026-09-27"))[.steps] == DailyValue(value: 20))
    }

    @Test func rebuildAllMarksEveryDayDirtyEvenWhenLocked() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.saveDailyValue(DailyValue(value: 10), type: .steps, day: day("2026-09-27"))
        try store.clearDirty(type: .steps, day: day("2026-09-27"))
        let health = FakeHealthSource()
        await health.setReadable(false)

        let outcome = await makeRunner(store: store, health: health).run(trigger: .rebuildAll, options: .forTrigger(.rebuildAll)) {}

        #expect(outcome.readOutcome == .skippedLocked)
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
    }

    @Test func aFreshDirtyEntryGetsItsValueRefreshed() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.saveDailyValue(DailyValue(value: 10), type: .steps, day: day("2026-09-27"))
        #expect(try store.dirtyEntries().first?.fresh == true)
        let health = FakeHealthSource()
        await health.setStatistic(99, for: .steps, day: day("2026-09-27"))

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dailyValues(day: day("2026-09-27"))[.steps] == DailyValue(value: 99))
    }

    @Test func rebuildVerifyRemovesTheEarliestLocalSampleHealthKitDeleted() async throws {
        let store = try LocalStore.inMemory()
        let gone = makeSample(start: "2026-01-05T12:00:00Z")
        let kept = makeSample(start: "2026-03-05T12:00:00Z")
        try store.applyChanges(HealthChanges(added: [gone, kept]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.clearDirty(type: .steps, day: day("2026-01-05"))
        try store.clearDirty(type: .steps, day: day("2026-03-05"))
        let health = FakeHealthSource()
        await health.setSamples([kept], for: .steps)
        await health.setEarliest(kept.start)

        _ = await makeRunner(store: store, health: health).run(trigger: .rebuildAll, options: RunOptions(read: true, verify: .allDates, markAllDirty: false)) {}

        #expect(try store.samples(type: .steps, month: "2026-01").isEmpty)
        #expect(try store.samples(type: .steps, month: "2026-03").map(\.uuid) == [kept.uuid])
        #expect(try store.dirtyEntries().map(\.day).contains(day("2026-01-05")))
    }

    @Test func rebuildVerifyClearsLocalSamplesWhenHealthKitIsEmpty() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-02-05T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.clearDirty(type: .steps, day: day("2026-02-05"))
        let health = FakeHealthSource()

        _ = await makeRunner(store: store, health: health).run(trigger: .rebuildAll, options: RunOptions(read: true, verify: .allDates, markAllDirty: false)) {}

        #expect(try store.samples(type: .steps, month: "2026-02").isEmpty)
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-02-05")])
    }

    @Test func aCancelledRunReadsNothingAndLeavesMarks() async throws {
        let store = try LocalStore.inMemory()
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")], newAnchor: Data([7])), for: .steps)
        await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
        let runner = makeRunner(store: store, health: health)
        let gate = AsyncStream<Void>.makeStream()
        let task = Task { () -> RunOutcome in
            for await _ in gate.stream {}
            return await runner.run(trigger: .appOpen, options: .forTrigger(.appOpen)) {}
        }
        task.cancel()
        gate.continuation.finish()
        let outcome = await task.value

        #expect(outcome.errors.isEmpty)
        #expect(log.all.isEmpty)
        #expect(try store.anchor(for: .steps) == nil)
        #expect(try store.samples(type: .steps, month: "2026-09").isEmpty)
        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func triggerOptionsMatchTheSpec() {
        #expect(RunOptions.forTrigger(.observerWake) == RunOptions(read: true, verify: .none, markAllDirty: false))
        #expect(RunOptions.forTrigger(.appOpen) == RunOptions(read: true, verify: .last30Days, markAllDirty: false))
        #expect(RunOptions.forTrigger(.backgroundRefresh) == RunOptions(read: true, verify: .last30Days, markAllDirty: false))
        #expect(RunOptions.forTrigger(.appIntent) == RunOptions(read: false, verify: .none, markAllDirty: false))
        #expect(RunOptions.forTrigger(.rebuildAll) == RunOptions(read: true, verify: .allDates, markAllDirty: true))
        #expect(RunOptions.forTrigger(.appIntent).merged(with: .forTrigger(.appOpen)) == RunOptions(read: true, verify: .last30Days, markAllDirty: false))
    }

    @Test func anExerciseDayStoresTheStatisticSumInMinutes() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(type: .exerciseMinutes, start: "2026-09-27T12:00:00Z", end: "2026-09-27T12:01:00Z", value: .quantity(60))]), for: .exerciseMinutes)
        await health.setStatistic(34.9, for: .exerciseMinutes, day: day("2026-09-27"))

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dailyValues(day: day("2026-09-27")) == [.exerciseMinutes: DailyValue(value: 34.9)])
    }

    @Test func aDayWithoutAnExerciseStatisticHasNoValue() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(type: .exerciseMinutes, start: "2026-09-27T12:00:00Z", end: "2026-09-27T12:01:00Z", value: .quantity(60))]), for: .exerciseMinutes)

        _ = await makeRunner(store: store, health: health).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(try store.dailyValues(day: day("2026-09-27"))[.exerciseMinutes] == nil)
    }
}
