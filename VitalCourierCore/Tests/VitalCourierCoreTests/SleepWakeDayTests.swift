import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct SleepWakeDayTests {
    let now = date("2026-09-30T15:00:00Z")
    let wakeDay = day("2026-09-28")
    let previousDay = day("2026-09-27")
    let note28 = "Vital Courier/daily/2026-09-28.md"

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
}
