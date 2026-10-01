import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct SleepWakeDayTests {
    let now = date("2026-09-30T15:00:00Z")
    let wakeDay = day("2026-09-28")
    let previousDay = day("2026-09-27")
    let note28 = "Vital Courier/daily/2026-09-28.md"
    let note27 = "Vital Courier/daily/2026-09-27.md"

    func sleepSample(start: String, end: String, source: String = "Watch", stage: String = "asleepCore", uuid: UUID = UUID()) -> HealthSample {
        makeSample(type: .sleep, start: start, end: end, value: .category(stage), source: source, device: "Apple Watch", zone: "UTC", uuid: uuid)
    }

    func clearAllMarks(_ store: LocalStore) throws {
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }
    }

    func isDirty(_ store: LocalStore, _ dayKey: DayKey) throws -> Bool {
        try store.dirtyEntries().contains { $0.type == .sleep && $0.day == dayKey }
    }

    @Test func aLatePreMidnightSegmentDirtiesTheWakeDay() throws {
        let store = try LocalStore.inMemory()
        let night = sleepSample(start: "2026-09-28T00:00:00Z", end: "2026-09-28T06:00:00Z")
        try store.applyChanges(HealthChanges(added: [night]), for: .sleep, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.applyChanges(HealthChanges(added: [sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-27T23:00:00Z")]), for: .sleep, fallbackTimeZone: utc)

        #expect(try isDirty(store, wakeDay))
        #expect(try isDirty(store, previousDay))
        // Not blanket end-day-plus-one: nothing beyond the night's wake day.
        #expect(try !isDirty(store, day("2026-09-29")))
    }

    @Test func aLateSegmentRewritesTheExportedNoteWithTheNewHours() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        let destination = FakeDestination()
        let fixedNow = now
        let runner = ExportRunner(store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { utc })
        await health.queue(HealthChanges(added: [sleepSample(start: "2026-09-28T00:00:00Z", end: "2026-09-28T06:00:00Z")]), for: .sleep)
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}
        #expect(destination.text(at: note28)?.contains("vc_sleep_hours: 6.00") == true)

        await health.queue(HealthChanges(added: [sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-27T23:00:00Z")]), for: .sleep)
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(destination.text(at: note28)?.contains("vc_sleep_hours: 7.00") == true)
        // No phantom one-hour night on the previous day.
        #expect(destination.text(at: note27)?.contains("vc_sleep") == false)
        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func deletingAPreMidnightSegmentDirtiesTheWakeDay() throws {
        let store = try LocalStore.inMemory()
        let early = UUID()
        try store.applyChanges(HealthChanges(added: [
            sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-27T23:00:00Z", uuid: early),
            sleepSample(start: "2026-09-28T00:00:00Z", end: "2026-09-28T06:00:00Z"),
        ]), for: .sleep, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.applyChanges(HealthChanges(deletedUUIDs: [early]), for: .sleep, fallbackTimeZone: utc)

        #expect(try isDirty(store, wakeDay))
    }

    @Test func rebuildAllDirtiesTheWakeDayOfANightStoredOnThePreviousDay() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-28T06:00:00Z")]), for: .sleep, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.markAllDirty()

        #expect(try isDirty(store, wakeDay))
        #expect(try isDirty(store, previousDay))
    }

    @Test func changingTheSleepSourceDirtiesEveryWakeDayWithSleep() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-28T06:00:00Z")]), for: .sleep, fallbackTimeZone: utc)
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-20T12:00:00Z")]), for: .steps, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.setSleepSourcePreference("Watch")

        #expect(try store.dirtyEntries() == [DirtyEntry(type: .sleep, day: wakeDay, fresh: false)])
    }

    @Test func settingTheSameSleepSourceAgainDirtiesNothing() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [sleepSample(start: "2026-09-27T22:00:00Z", end: "2026-09-28T06:00:00Z")]), for: .sleep, fallbackTimeZone: utc)
        try store.setSleepSourcePreference("Watch")
        try clearAllMarks(store)

        try store.setSleepSourcePreference("Watch")
        #expect(try store.dirtyEntries().isEmpty)

        try store.setSleepSourcePreference(nil)
        #expect(try isDirty(store, wakeDay))
        try clearAllMarks(store)
        try store.setSleepSourcePreference(nil)
        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func aLateSegmentThatBridgesTwoNightsDirtiesBothWakeDays() async throws {
        let store = try LocalStore.inMemory()
        let health = FakeHealthSource()
        let destination = FakeDestination()
        let fixedNow = now
        let runner = ExportRunner(store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { utc })
        await health.queue(HealthChanges(added: [
            sleepSample(start: "2026-09-27T20:00:00Z", end: "2026-09-27T23:00:00Z"),
            sleepSample(start: "2026-09-28T05:00:00Z", end: "2026-09-28T06:00:00Z"),
        ]), for: .sleep)
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}
        #expect(destination.text(at: note27)?.contains("vc_sleep_hours: 3.00") == true)
        #expect(destination.text(at: note28)?.contains("vc_sleep_hours: 1.00") == true)

        let bridge = sleepSample(start: "2026-09-28T01:00:00Z", end: "2026-09-28T03:00:00Z")
        try store.applyChanges(HealthChanges(added: [bridge]), for: .sleep, fallbackTimeZone: utc)
        #expect(try isDirty(store, previousDay))
        #expect(try isDirty(store, wakeDay))

        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        #expect(destination.text(at: note28)?.contains("vc_sleep_hours: 6.00") == true)
        #expect(destination.text(at: note27)?.contains("vc_sleep") == false)
    }

    @Test func aChainLongerThanThreeDaysRedirtiesTheFarWakeDay() throws {
        let store = try LocalStore.inMemory()
        let start = date("2026-09-20T00:00:00Z")
        // Three hours asleep, three awake, for five days: one cluster, because every gap is under four hours.
        let chain = (0..<20).map { index -> HealthSample in
            let segmentStart = start.addingTimeInterval(Double(index) * 6 * 3600)
            return makeSample(type: .sleep, start: ISO8601DateFormatter().string(from: segmentStart), end: ISO8601DateFormatter().string(from: segmentStart.addingTimeInterval(3 * 3600)), value: .category("asleepCore"), source: "Watch", device: "Apple Watch", zone: "UTC")
        }
        try store.applyChanges(HealthChanges(added: chain), for: .sleep, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.applyChanges(HealthChanges(deletedUUIDs: [chain[0].uuid]), for: .sleep, fallbackTimeZone: utc)

        #expect(try isDirty(store, day("2026-09-24")))
    }

    @Test func aChainLongerThanTwoWeeksStillReachesTheFarWakeDayAndCountsEverySegment() async throws {
        let store = try LocalStore.inMemory()
        let start = date("2026-09-01T00:00:00Z")
        let formatter = ISO8601DateFormatter()
        // Three hours asleep, three awake, for sixteen days: 64 segments in one cluster that wakes on Sep 16.
        let chain = (0..<64).map { index -> HealthSample in
            let segmentStart = start.addingTimeInterval(Double(index) * 6 * 3600)
            return makeSample(type: .sleep, start: formatter.string(from: segmentStart), end: formatter.string(from: segmentStart.addingTimeInterval(3 * 3600)), value: .category("asleepCore"), source: "Watch", device: "Apple Watch", zone: "UTC")
        }
        let farWakeDay = day("2026-09-16")
        try store.applyChanges(HealthChanges(added: chain), for: .sleep, fallbackTimeZone: utc)
        try clearAllMarks(store)

        try store.applyChanges(HealthChanges(deletedUUIDs: [chain[0].uuid]), for: .sleep, fallbackTimeZone: utc)
        #expect(try isDirty(store, farWakeDay))

        let health = FakeHealthSource()
        let fixedNow = now
        let runner = ExportRunner(store: store, health: health, destination: { nil }, now: { fixedNow }, timeZone: { utc })
        _ = await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}

        let night = try #require(try store.dailyValues(day: farWakeDay)[.sleep])
        #expect(night.value == 63 * 3)
    }
}
