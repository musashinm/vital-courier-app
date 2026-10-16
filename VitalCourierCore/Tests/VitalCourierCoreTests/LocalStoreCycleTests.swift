import Foundation
import GRDB
import Testing
@testable import VitalCourierCore

@Suite struct LocalStoreCycleTests {
    func flowSample(_ value: String, start: String) -> HealthSample {
        makeSample(type: .menstrualFlow, start: start, value: .category(value))
    }

    @Test func eachTypeFillsItsOwnColumnsOfTheDayRow() throws {
        let store = try LocalStore.inMemory()
        try store.saveCycleDay(.flow("medium", periodStart: true), day: day("2026-10-12"))
        try store.saveCycleDay(.spotting(true), day: day("2026-10-12"))
        #expect(try store.cycleDay(day: day("2026-10-12")) == CycleDay(flow: "medium", periodStart: true, spotting: true))

        try store.saveCycleDay(.flow(nil, periodStart: false), day: day("2026-10-12"))
        #expect(try store.cycleDay(day: day("2026-10-12")) == CycleDay(spotting: true))
    }

    @Test func aDayWithNothingLeftLosesItsRow() throws {
        let store = try LocalStore.inMemory()
        try store.saveCycleDay(.spotting(true), day: day("2026-10-12"))
        try store.saveCycleDay(.spotting(false), day: day("2026-10-12"))
        #expect(try store.cycleDay(day: day("2026-10-12")) == nil)
        let rowCount = try store.dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cycleDailyValue") }
        #expect(rowCount == 0)
    }

    @Test func savingMarksThatTypesDirtyEntryFresh() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [flowSample("light", start: "2026-10-12T12:00:00Z")]), for: .menstrualFlow, fallbackTimeZone: saoPaulo)
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .menstrualFlow, day: day("2026-10-12"), fresh: false)])

        try store.saveCycleDay(.flow("light", periodStart: false), day: day("2026-10-12"))

        #expect(try store.dirtyEntries() == [DirtyEntry(type: .menstrualFlow, day: day("2026-10-12"), fresh: true)])
    }

    @Test func deletingDirtyMarksLeavesOtherTypesAndStoredData() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [flowSample("light", start: "2026-10-12T12:00:00Z")]), for: .menstrualFlow, fallbackTimeZone: saoPaulo)
        try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-10-12T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
        try store.saveCycleDay(.flow("light", periodStart: false), day: day("2026-10-12"))

        try store.deleteDirtyMarks(types: HealthType.cycleTypes)

        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-10-12"), fresh: false)])
        #expect(try store.samples(type: .menstrualFlow, month: "2026-10").count == 1)
        #expect(try store.cycleDay(day: day("2026-10-12")) == CycleDay(flow: "light"))
    }

    @Test func clearLocalCopyAlsoClearsCycleDays() throws {
        let store = try LocalStore.inMemory()
        try store.saveCycleDay(.flow("heavy", periodStart: true), day: day("2026-10-12"))

        try store.clearLocalCopy()

        #expect(try store.cycleDay(day: day("2026-10-12")) == nil)
    }

    @Test func rebuildAllMarksOnlyTheGivenTypes() throws {
        let store = try LocalStore.inMemory()
        try store.applyChanges(HealthChanges(added: [flowSample("light", start: "2026-10-12T12:00:00Z")]), for: .menstrualFlow, fallbackTimeZone: saoPaulo)
        try store.applyChanges(HealthChanges(added: [makeSample(type: .weight, start: "2026-10-12T12:00:00Z", value: .quantity(70))]), for: .weight, fallbackTimeZone: saoPaulo)
        try store.deleteDirtyMarks(types: HealthType.allCases)

        try store.markAllDirty(statisticsZone: saoPaulo, types: HealthType.baseTypes)

        #expect(try store.dirtyEntries() == [DirtyEntry(type: .weight, day: day("2026-10-12"), fresh: false)])
    }

    @Test func existingDataSurvivesTheCycleMigration() throws {
        let dbQueue = try DatabaseQueue()
        try LocalStore.migrator.migrate(dbQueue, upTo: "v1")
        let sampleUUID = UUID()
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sample (uuid, type, startTime, endTime, valueNumber, valueText, source, device, metadata, zone, day, month)
                VALUES (?, 'steps', 1790000000, 1790000060, 812, NULL, 'iPhone', 'iPhone', '{}', 'America/Sao_Paulo', '2026-09-21', '2026-09')
                """, arguments: [sampleUUID.uuidString])
            try db.execute(sql: "INSERT INTO dailyValue (type, day, value, deepHours, remHours, source) VALUES ('sleep', '2026-09-21', 7.5, 1.2, 1.6, 'Apple Watch')")
            try db.execute(sql: "INSERT INTO dirty (type, day, fresh) VALUES ('steps', '2026-09-21', 0)")
            try db.execute(sql: "INSERT INTO anchor (type, data) VALUES ('steps', x'01')")
            try db.execute(sql: "INSERT INTO setting (settingKey, settingValue) VALUES ('sleepSourcePreference', 'Apple Watch')")
            try db.execute(sql: "INSERT INTO runRecord (startedAt, triggerName, readOutcome, daysWritten, daysFailed, daysPending, errors) VALUES (1790000000, 'appOpen', 'read', 1, 0, 0, '[]')")
        }

        let store = try LocalStore(dbQueue: dbQueue)

        #expect(try store.samples(type: .steps, month: "2026-09").map(\.uuid) == [sampleUUID])
        #expect(try store.samples(type: .steps, month: "2026-09").map(\.value) == [.quantity(812)])
        #expect(try store.dailyValues(day: day("2026-09-21"))[.sleep] == DailyValue(value: 7.5, deepHours: 1.2, remHours: 1.6, source: "Apple Watch"))
        #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-21"), fresh: false)])
        #expect(try store.anchor(for: .steps) == Data([1]))
        #expect(try store.sleepSourcePreference() == "Apple Watch")
        #expect(try store.recentRuns(limit: 1).first?.trigger == "appOpen")
        let cycleRowCount = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cycleDailyValue") }
        #expect(cycleRowCount == 0)
        #expect(try store.cycleDay(day: day("2026-09-21")) == nil)
    }
}
