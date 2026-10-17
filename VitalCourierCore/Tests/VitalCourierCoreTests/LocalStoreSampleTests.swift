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
        // The row keeps its Sao Paulo day (the 26th); the statistics query now runs in Lisbon, where the sample falls on the 27th, so that day is dirty too.
        #expect(try store.dirtyEntries().map(\.day) == [day("2026-09-26"), day("2026-09-27")])
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

    // MARK: Samples that cross midnight

    func dirtyDays(_ store: LocalStore, type: HealthType) throws -> [DayKey] {
        try store.dirtyEntries().filter { $0.type == type }.map(\.day)
    }

    @Test func aSampleInsideOneDayOverlapsOnlyThatDay() {
        let days = LocalStore.overlappedDays(start: date("2026-09-27T15:00:00Z"), end: date("2026-09-27T16:00:00Z"), zone: saoPaulo)
        #expect(days == [day("2026-09-27")])
    }

    @Test func aSampleAcrossMidnightOverlapsBothDays() {
        // 23:30 on the 27th to 00:30 on the 28th, Sao Paulo time.
        let days = LocalStore.overlappedDays(start: date("2026-09-28T02:30:00Z"), end: date("2026-09-28T03:30:00Z"), zone: saoPaulo)
        #expect(days == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func aSampleEndingExactlyAtMidnightOverlapsOnlyItsStartDay() {
        let days = LocalStore.overlappedDays(start: date("2026-09-28T02:00:00Z"), end: date("2026-09-28T03:00:00Z"), zone: saoPaulo)
        #expect(days == [day("2026-09-27")])
    }

    @Test func aZeroLengthOrBackwardsSampleOverlapsItsStartDay() {
        let instant = date("2026-09-28T02:59:59Z")
        #expect(LocalStore.overlappedDays(start: instant, end: instant, zone: saoPaulo) == [day("2026-09-27")])
        #expect(LocalStore.overlappedDays(start: instant, end: date("2026-09-20T00:00:00Z"), zone: saoPaulo) == [day("2026-09-27")])
    }

    @Test func aThreeDaySampleOverlapsEveryDayItTouches() {
        let days = LocalStore.overlappedDays(start: date("2026-09-27T15:00:00Z"), end: date("2026-09-29T15:00:00Z"), zone: saoPaulo)
        #expect(days == [day("2026-09-27"), day("2026-09-28"), day("2026-09-29")])
    }

    @Test func calendarDaySteppingSurvivesTheSpringForwardDay() {
        let newYork = TimeZone(identifier: "America/New_York")!
        // 23:00 EST on March 7 to 01:00 EDT on March 9: three local days, the middle one only 23 hours long.
        let across = LocalStore.overlappedDays(start: date("2026-03-08T04:00:00Z"), end: date("2026-03-09T05:00:00Z"), zone: newYork)
        #expect(across == [day("2026-03-07"), day("2026-03-08"), day("2026-03-09")])
        // 00:30 EST on March 8 to 00:00 EDT on March 9: the end is the next midnight, so only March 8.
        let shortDay = LocalStore.overlappedDays(start: date("2026-03-08T05:30:00Z"), end: date("2026-03-09T04:00:00Z"), zone: newYork)
        #expect(shortDay == [day("2026-03-08")])
    }

    @Test func addingAStepsSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .steps) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func deletingAStepsSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.applyChanges(HealthChanges(deletedUUIDs: [sample.uuid]), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .steps) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func aRestingHeartRateSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .restingHeartRate, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .restingHeartRate, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .restingHeartRate) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func aWalkingHeartRateSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .walkingHeartRateAverage, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .walkingHeartRateAverage, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .walkingHeartRateAverage) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func aHeartRateSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .heartRate, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .heartRate, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .heartRate) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func aReplacedWalkingHeartRateEstimateDirtiesItsDayAndKeepsOnlyTheNewSample() throws {
        let store = try LocalStore.inMemory()
        let original = makeSample(type: .walkingHeartRateAverage, start: "2026-09-27T15:00:00Z", end: "2026-09-27T15:01:00Z", value: .quantity(1.5))
        try store.applyChanges(HealthChanges(added: [original]), for: .walkingHeartRateAverage, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        let replacement = makeSample(type: .walkingHeartRateAverage, start: "2026-09-27T16:00:00Z", end: "2026-09-27T16:01:00Z", value: .quantity(1.54))
        try store.applyChanges(HealthChanges(added: [replacement], deletedUUIDs: [original.uuid]), for: .walkingHeartRateAverage, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .walkingHeartRateAverage) == [day("2026-09-27")])
        #expect(try store.samples(type: .walkingHeartRateAverage, fromDay: day("2026-09-27"), toDay: day("2026-09-27")).map(\.uuid) == [replacement.uuid])
    }

    @Test func aWeightSampleAcrossMidnightDirtiesOnlyItsStartDay() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .weight, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .weight, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .weight) == [day("2026-09-27")])
    }

    @Test func aStoredZoneDifferentFromTheQueryZoneDirtiesTheQueryZoneDays() throws {
        let store = try LocalStore.inMemory()
        // 03:30 to 04:30 in Lisbon is 23:30 on the 27th to 00:30 on the 28th in Sao Paulo, where the statistics are queried.
        let sample = makeSample(start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "Europe/Lisbon")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .steps) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllDirtiesTheSecondDayOfAStoredCrossingSample() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "UTC")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo)

        // Stored zone UTC keeps the sample on the 28th only; Sao Paulo, the statistics zone, adds the 27th.
        #expect(try dirtyDays(store, type: .steps) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllDirtiesTheSecondDayInTheStoredZone() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "America/Sao_Paulo")
        try store.applyChanges(HealthChanges(added: [sample]), for: .steps, fallbackTimeZone: lisbon)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: lisbon)

        // Stored zone Sao Paulo splits the sample across the 27th and 28th; Lisbon alone would keep it on the 28th.
        #expect(try dirtyDays(store, type: .steps) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllMarksTheSameDaysForAHeartRateSampleWhoseStartDayDiffersBetweenZones() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .heartRate, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "UTC")
        try store.applyChanges(HealthChanges(added: [sample]), for: .heartRate, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo)

        #expect(try dirtyDays(store, type: .heartRate) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllMarksEveryDayOfALargeHeartRateHistory() throws {
        let store = try LocalStore.inMemory()
        let sampleCount = 50_000
        let batchSize = 2_000
        let firstStart = date("2026-01-01T03:00:00Z")
        for batchStart in stride(from: 0, to: sampleCount, by: batchSize) {
            let samples = (batchStart..<batchStart + batchSize).map { minute in
                let start = firstStart.addingTimeInterval(Double(minute) * 60)
                return HealthSample(
                    uuid: UUID(), type: .heartRate, start: start, end: start.addingTimeInterval(1),
                    value: .quantity(60), source: "Watch", device: "Apple Watch", metadata: [:],
                    timeZoneIdentifier: "America/Sao_Paulo"
                )
            }
            try store.applyChanges(HealthChanges(added: samples), for: .heartRate, fallbackTimeZone: saoPaulo)
        }
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo, types: [.heartRate])

        let lastStart = firstStart.addingTimeInterval(Double(sampleCount - 1) * 60)
        let lastDay = DayKey(date: lastStart, timeZone: saoPaulo)
        var expectedDays: [DayKey] = []
        var current = day("2026-01-01")
        while current <= lastDay {
            expectedDays.append(current)
            current = current.adding(days: 1)
        }
        #expect(try dirtyDays(store, type: .heartRate) == expectedDays)
    }

    @Test func addingAnExerciseSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .exerciseMinutes, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .exerciseMinutes) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func deletingAnExerciseSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .exerciseMinutes, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z")
        try store.applyChanges(HealthChanges(added: [sample]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.applyChanges(HealthChanges(deletedUUIDs: [sample.uuid]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .exerciseMinutes) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func anExerciseSampleInAnotherStoredZoneDirtiesTheQueryZoneDays() throws {
        let store = try LocalStore.inMemory()
        // 03:30 to 04:30 in Lisbon is 23:30 on the 27th to 00:30 on the 28th in Sao Paulo, where the statistics are queried.
        let sample = makeSample(type: .exerciseMinutes, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "Europe/Lisbon")
        try store.applyChanges(HealthChanges(added: [sample]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .exerciseMinutes) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllDirtiesBothDaysOfAStoredCrossingExerciseSample() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .exerciseMinutes, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "UTC")
        try store.applyChanges(HealthChanges(added: [sample]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo)

        // Stored zone UTC keeps the sample on the 28th only; Sao Paulo, the statistics zone, adds the 27th.
        #expect(try dirtyDays(store, type: .exerciseMinutes) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllLimitedToOtherTypesLeavesExerciseClean() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .exerciseMinutes, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", zone: "UTC")
        try store.applyChanges(HealthChanges(added: [sample]), for: .exerciseMinutes, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo, types: [.steps])

        #expect(try dirtyDays(store, type: .exerciseMinutes).isEmpty)
    }

    @Test func addingARespiratorySampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .respiratoryRate, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", value: .quantity(0.25))
        try store.applyChanges(HealthChanges(added: [sample]), for: .respiratoryRate, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .respiratoryRate) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func addingAGlucoseSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .bloodGlucose, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", value: .quantity(1.04))
        try store.applyChanges(HealthChanges(added: [sample]), for: .bloodGlucose, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .bloodGlucose) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func addingABloodOxygenSampleAcrossMidnightDirtiesBothDays() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .bloodOxygen, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", value: .quantity(0.96))
        try store.applyChanges(HealthChanges(added: [sample]), for: .bloodOxygen, fallbackTimeZone: saoPaulo)

        #expect(try dirtyDays(store, type: .bloodOxygen) == [day("2026-09-27"), day("2026-09-28")])
    }

    @Test func rebuildAllDirtiesBothDaysOfAStoredCrossingRespiratorySample() throws {
        let store = try LocalStore.inMemory()
        let sample = makeSample(type: .respiratoryRate, start: "2026-09-28T02:30:00Z", end: "2026-09-28T03:30:00Z", value: .quantity(0.25), zone: "UTC")
        try store.applyChanges(HealthChanges(added: [sample]), for: .respiratoryRate, fallbackTimeZone: saoPaulo)
        for entry in try store.dirtyEntries() { try store.clearDirty(type: entry.type, day: entry.day) }

        try store.markAllDirty(statisticsZone: saoPaulo)

        // Stored zone UTC keeps the sample on the 28th only; Sao Paulo, the statistics zone, adds the 27th.
        #expect(try dirtyDays(store, type: .respiratoryRate) == [day("2026-09-27"), day("2026-09-28")])
    }
}
