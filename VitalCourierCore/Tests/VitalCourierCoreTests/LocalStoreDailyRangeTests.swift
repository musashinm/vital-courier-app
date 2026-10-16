import Foundation
import GRDB
import Testing
@testable import VitalCourierCore

@Suite struct LocalStoreDailyRangeTests {
    @Test func existingDailyValuesSurviveTheRangeMigration() throws {
        let dbQueue = try DatabaseQueue()
        try LocalStore.migrator.migrate(dbQueue, upTo: "v2-cycleDailyValue")
        try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO dailyValue (type, day, value, deepHours, remHours, source) VALUES ('sleep', '2026-10-14', 7.5, 1.2, 1.6, 'Apple Watch')")
            try db.execute(sql: "INSERT INTO dailyValue (type, day, value, deepHours, remHours, source) VALUES ('steps', '2026-10-14', 8412, NULL, NULL, NULL)")
            try db.execute(sql: "INSERT INTO cycleDailyValue (day, flow, periodStart, spotting) VALUES ('2026-10-14', 'light', 1, NULL)")
        }

        let store = try LocalStore(dbQueue: dbQueue)

        let values = try store.dailyValues(day: day("2026-10-14"))
        #expect(values[.sleep] == DailyValue(value: 7.5, deepHours: 1.2, remHours: 1.6, source: "Apple Watch"))
        #expect(values[.steps] == DailyValue(value: 8412))
        #expect(values[.sleep]?.minimum == nil)
        #expect(values[.sleep]?.maximum == nil)
        #expect(try store.cycleDay(day: day("2026-10-14")) == CycleDay(flow: "light", periodStart: true, spotting: false))
    }

    @Test func aRespiratoryRangeRoundTripsAndANilRangeClearsIt() throws {
        let store = try LocalStore.inMemory()
        try store.saveDailyValue(DailyValue(value: 14.5, minimum: 12.1, maximum: 17), type: .respiratoryRate, day: day("2026-10-14"))
        #expect(try store.dailyValues(day: day("2026-10-14"))[.respiratoryRate] == DailyValue(value: 14.5, minimum: 12.1, maximum: 17))

        // A reread without a range must not keep the old one.
        try store.saveDailyValue(DailyValue(value: 14.8), type: .respiratoryRate, day: day("2026-10-14"))
        #expect(try store.dailyValues(day: day("2026-10-14"))[.respiratoryRate] == DailyValue(value: 14.8))
    }
}
