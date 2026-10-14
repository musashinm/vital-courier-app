import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct ExportRunnerCycleTests {
    let now = date("2026-10-13T15:00:00Z")
    let flowJSON = "Vital Courier/json/menstrual-flow/2026-10.json"
    let spottingJSON = "Vital Courier/json/spotting/2026-10.json"
    let note12 = "Vital Courier/daily/2026-10-12.md"

    func makeRunner(store: LocalStore, health: FakeHealthSource, destination: FakeDestination?, cycleTrackingEnabled: Bool) -> ExportRunner {
        let fixedNow = now
        return ExportRunner(
            store: store,
            health: health,
            destination: { destination },
            now: { fixedNow },
            timeZone: { saoPaulo },
            enabledTypes: { HealthType.enabledTypes(cycleTrackingEnabled: cycleTrackingEnabled) }
        )
    }

    func flowSample(_ value: String, start: String, cycleStart: Bool = false) -> HealthSample {
        makeSample(type: .menstrualFlow, start: start, value: .category(value), metadata: [CycleDayRule.menstrualCycleStartMetadataKey: cycleStart ? "1" : "0"])
    }

    @Test func withTrackingOnAFlowDayGetsItsCycleRowAndJSON() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        let destination = FakeDestination()
        // 08:00 and 17:00 on the 12th, Sao Paulo time.
        await health.queue(HealthChanges(added: [flowSample("light", start: "2026-10-12T11:00:00Z", cycleStart: true), flowSample("heavy", start: "2026-10-12T20:00:00Z")]), for: .menstrualFlow)
        await health.queue(HealthChanges(added: [makeSample(type: .spotting, start: "2026-10-12T15:00:00Z", value: .category("notApplicable"))]), for: .spotting)

        let outcome = await makeRunner(store: store, health: health, destination: destination, cycleTrackingEnabled: true).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(outcome.daysWritten == 1)
        #expect(try store.cycleDay(day: day("2026-10-12")) == CycleDay(flow: "heavy", periodStart: true, spotting: true))
        #expect(destination.paths.contains(flowJSON))
        #expect(destination.paths.contains(spottingJSON))
        #expect(destination.text(at: flowJSON)?.contains("\"heavy\"") == true)
        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func withTrackingOffTheCycleTypesAreNeitherReadNorWritten() async throws {
        let store = try LocalStore.inMemory()
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        let destination = FakeDestination()
        await health.queue(HealthChanges(added: [flowSample("medium", start: "2026-10-12T11:00:00Z")]), for: .menstrualFlow)

        _ = await makeRunner(store: store, health: health, destination: destination, cycleTrackingEnabled: false).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(log.all.contains("changes steps"))
        #expect(!log.all.contains("changes menstrualFlow"))
        #expect(!log.all.contains("changes spotting"))
        #expect(!destination.paths.contains(flowJSON))
        #expect(try store.dirtyEntries().allSatisfy { !HealthType.cycleTypes.contains($0.type) })
    }

    @Test func withTrackingOffStoredCycleMarksAreSkippedByDailyValuesAndWrite() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [flowSample("medium", start: "2026-10-12T11:00:00Z")]), for: .menstrualFlow, fallbackTimeZone: saoPaulo)
        let destination = FakeDestination()

        let outcome = await makeRunner(store: store, health: FakeHealthSource(), destination: destination, cycleTrackingEnabled: false).run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(outcome.daysWritten == 0)
        #expect(try store.cycleDay(day: day("2026-10-12")) == nil)
        #expect(destination.paths.isEmpty)
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .menstrualFlow, day: day("2026-10-12"), fresh: false)])
    }

    @Test func withTrackingOffRebuildAllSkipsTheCycleTypes() async throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [flowSample("medium", start: "2026-10-12T11:00:00Z")]), for: .menstrualFlow, fallbackTimeZone: saoPaulo)
        try store.deleteDirtyMarks(types: HealthType.allCases)
        let log = EventLog()
        let health = FakeHealthSource(log: log)
        // Verify's all-dates path returns early without an earliest date; the stored flow sample doesn't count while tracking is off.
        await health.setEarliest(date("2026-10-01T00:00:00Z"))
        let destination = FakeDestination()

        _ = await makeRunner(store: store, health: health, destination: destination, cycleTrackingEnabled: false).run(trigger: .rebuildAll, options: .forTrigger(.rebuildAll)) {}

        #expect(!log.all.contains("samples menstrualFlow"))
        #expect(!destination.paths.contains(flowJSON))
        #expect(try store.dirtyEntries().allSatisfy { $0.type != .menstrualFlow })
        #expect(try store.samples(type: .menstrualFlow, month: "2026-10").count == 1)
        #expect(await health.earliestRequestedTypes == [HealthType.baseTypes])
    }
}
