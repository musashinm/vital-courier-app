import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct ExportRunnerWriteTests {
    let now = date("2026-09-30T15:00:00Z")
    let stepsJSON = "Vital Courier/json/steps/2026-09.json"
    let note27 = "Vital Courier/daily/2026-09-27.md"

    func makeRunner(store: LocalStore, health: FakeHealthSource, destination: FakeDestination?) -> ExportRunner {
        let fixedNow = now
        return ExportRunner(store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { saoPaulo })
    }

    func readableRunWithOneStepsSample(store: LocalStore, destination: FakeDestination?) async -> RunOutcome {
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)
        await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
        return await makeRunner(store: store, health: health, destination: destination).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}
    }

    @Test func aFreshDayWritesJSONNoteAndReadmeThenClearsItsMarks() async throws {
        let store = try LocalStore.inMemory()
        let destination = FakeDestination()

        let outcome = await readableRunWithOneStepsSample(store: store, destination: destination)

        #expect(outcome.daysWritten == 1)
        #expect(destination.paths == [stepsJSON, note27, "Vital Courier/README.md"])
        #expect(destination.text(at: note27)?.contains("vc_steps: 8412") == true)
        #expect(try store.dirtyEntries().isEmpty)
        let run = try #require(try store.recentRuns(limit: 1).first)
        #expect(run.trigger == "observerWake")
        #expect(run.readOutcome == "read")
        #expect(run.daysWritten == 1)
    }

    @Test func aLockedRunWritesJSONButSkipsNotesWithStaleValues() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        let health = FakeHealthSource()
        await health.setReadable(false)
        let destination = FakeDestination()

        let outcome = await makeRunner(store: store, health: health, destination: destination).run(trigger: .appIntent, options: .forTrigger(.appIntent)) {}

        #expect(destination.paths == [stepsJSON])
        #expect(outcome.daysPending == 1)
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
    }

    @Test func aFailedJSONWriteOnAStaleDayCountsAsFailed() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        let health = FakeHealthSource()
        await health.setReadable(false)
        let destination = FakeDestination()
        destination.failWrites(to: stepsJSON)

        let outcome = await makeRunner(store: store, health: health, destination: destination).run(trigger: .appIntent, options: .forTrigger(.appIntent)) {}

        #expect(outcome.daysFailed == 1)
        #expect(outcome.daysPending == 0)
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
    }

    @Test func aFailedNoteWriteKeepsTheMarks() async throws {
        let store = try LocalStore.inMemory()
        let destination = FakeDestination()
        destination.failWrites(to: note27)

        let outcome = await readableRunWithOneStepsSample(store: store, destination: destination)

        #expect(outcome.daysFailed == 1)
        #expect(outcome.errors.count == 1)
        #expect(destination.paths == [stepsJSON])
        #expect(try store.dirtyEntries().count == 1)
    }

    @Test func withNoFolderNothingIsWrittenAndMarksStay() async throws {
        let store = try LocalStore.inMemory()

        let outcome = await readableRunWithOneStepsSample(store: store, destination: nil)

        #expect(outcome.errors == ["no folder picked"])
        #expect(outcome.daysPending == 1)
        #expect(try store.dirtyEntries().count == 1)
        #expect(try store.recentRuns(limit: 1).first?.errors == ["no folder picked"])
    }

    @Test func deletingTheLastSampleOfADayDropsTheKeyFromTheNote() async throws {
        let store = try LocalStore.inMemory()
        let destination = FakeDestination()
        let sample = makeSample(start: "2026-09-27T12:00:00Z")
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [sample]), for: .steps)
        await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
        let runner = makeRunner(store: store, health: health, destination: destination)
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        await health.queue(HealthChanges(deletedUUIDs: [sample.uuid]), for: .steps)
        await health.setStatistic(nil, for: .steps, day: day("2026-09-27"))
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        let note = try #require(destination.text(at: note27))
        #expect(!note.contains("vc_steps"))
        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func oneStaleTypeHoldsBackTheWholeDaysNote() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)
        await health.queue(HealthChanges(added: [makeSample(type: .restingHeartRate, start: "2026-09-27T12:00:00Z", value: .quantity(1))]), for: .restingHeartRate)
        await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
        await health.failStatistic(for: .restingHeartRate, day: day("2026-09-27"))
        let destination = FakeDestination()

        let outcome = await makeRunner(store: store, health: health, destination: destination).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(destination.text(at: note27) == nil)
        #expect(outcome.daysPending == 1)
        #expect(Set(try store.dirtyEntries().map(\.type)) == [.steps, .restingHeartRate])
    }

    @Test func aMonthFileIsWrittenOncePerRun() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z"), makeSample(start: "2026-09-28T12:00:00Z")]), for: .steps)
        await health.setStatistic(1, for: .steps, day: day("2026-09-27"))
        await health.setStatistic(2, for: .steps, day: day("2026-09-28"))
        let destination = FakeDestination()

        let outcome = await makeRunner(store: store, health: health, destination: destination).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(outcome.daysWritten == 2)
        #expect(destination.writeCount(at: stepsJSON) == 1)
    }

    @Test func aCancelledRunStopsAndLeavesTheRestDirty() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z"), makeSample(start: "2026-09-28T12:00:00Z")]), for: .steps)
        await health.setStatistic(1, for: .steps, day: day("2026-09-27"))
        await health.setStatistic(2, for: .steps, day: day("2026-09-28"))
        let destination = FakeDestination()
        destination.cancelCurrentTaskOnFirstWrite()

        let runner = makeRunner(store: store, health: health, destination: destination)
        // Its own task, so the cancellation the fake triggers never touches the test's task.
        let outcome = await Task { await runner.run(trigger: .backgroundRefresh, options: .forTrigger(.observerWake)) {} }.value

        #expect(outcome.daysWritten == 1)
        #expect(outcome.daysPending == 1)
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-28")])
    }
}
