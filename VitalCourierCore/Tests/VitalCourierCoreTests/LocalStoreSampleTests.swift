import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct LocalStoreSampleTests {
    @Test func insertsSamplesMarksTheirDayDirtyAndSavesTheAnchor() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-27T12:00:00Z")
        try store.applyChanges(HealthChanges(added: [sample], newAnchor: Data([1, 2])), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try store.samples(type: .steps, month: "2026-09").map(\.uuid) == [sample.uuid])
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
        #expect(try store.anchor(for: .steps) == Data([1, 2]))
        #expect(try store.anchor(for: .weight) == nil)
    }

    @Test func theSameUUIDTwiceKeepsOneRowAndItsFirstDay() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-27T01:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)
        // Same sample again after a trip: the phone is now in Lisbon, where it would land on the 27th.
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: lisbon)

        let stored = try store.samples(type: .steps, month: "2026-09")
        #expect(stored.count == 1)
        #expect(stored.first?.timeZoneIdentifier == "America/Sao_Paulo")
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-26")])
    }

    @Test func deletionRemovesTheRowAndMarksItsDayDirty() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-27T12:00:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.applyChanges(HealthChanges(deletedUUIDs: [sample.uuid, UUID()]), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try store.samples(type: .steps, month: "2026-09").isEmpty)
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-27")])
    }

    @Test func aSleepSampleMarksItsStartDayAndItsWakeDay() throws {
        let store = try LocalStore.inMemory()
        // 23:00 on the 26th to 07:00 on the 27th, Sao Paulo time.
        let sample = makeSample(type: .sleep, start: "2026-09-27T02:00:00Z", end: "2026-09-27T10:00:00Z", value: .category("asleepCore"))
        try store.applyChanges(HealthChanges(added: [sample]), for: .sleep, fallbackTimeZone: saoPaulo)

        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-26"), day("2026-09-27")])
    }

    @Test func readsSamplesByDayRangeAndUUIDsByStartInterval() throws {
        let store = try LocalStore.inMemory()
        let first = makeSample(start: "2026-09-26T15:00:00Z")
        let second = makeSample(start: "2026-09-27T15:00:00Z")
        let third = makeSample(start: "2026-09-28T15:00:00Z")
        try store.applyChanges(HealthChanges(added: [first, second, third]), for: .steps, fallbackTimeZone: saoPaulo)

        let range = try store.samples(type: .steps, fromDay: day("2026-09-26"), toDay: day("2026-09-27"))
        #expect(range.map(\.uuid) == [first.uuid, second.uuid])

        let interval = DateInterval(start: date("2026-09-27T00:00:00Z"), end: date("2026-09-29T00:00:00Z"))
        #expect(try store.sampleUUIDs(type: .steps, startingIn: interval) == [second.uuid, third.uuid])
    }

    @Test func roundTripsEveryField() throws {
        let store = try LocalStore.inMemory()
        var sample = makeSample(type: .sleep, start: "2026-09-27T02:00:00Z", end: "2026-09-27T03:00:00Z", value: .category("asleepREM"), source: "Watch", device: "Apple Watch", zone: "Europe/Lisbon")
        sample.metadata = ["HKTimeZone": "Europe/Lisbon"]
        try store.applyChanges(HealthChanges(added: [sample]), for: .sleep, fallbackTimeZone: saoPaulo)

        #expect(try store.samples(type: .sleep, month: "2026-09") == [sample])
    }

    @Test func openOnDiskCreatesTheDatabaseAndExcludesItFromBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LocalStore.open(directory: directory)

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("local-store.sqlite").path))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
