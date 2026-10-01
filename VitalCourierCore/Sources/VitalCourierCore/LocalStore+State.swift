import Foundation
import GRDB

public struct DailyValue: Equatable, Sendable {
    /// Steps: count. Resting heart rate: beats per minute. Weight: kg. Sleep: asleep hours.
    public var value: Double
    public var deepHours: Double?
    public var remHours: Double?
    /// Sleep only: the source the night's totals came from.
    public var source: String?

    public init(value: Double, deepHours: Double? = nil, remHours: Double? = nil, source: String? = nil) {
        self.value = value
        self.deepHours = deepHours
        self.remHours = remHours
        self.source = source
    }
}

public struct RunRecord: Equatable, Sendable {
    public var startedAt: Date
    public var trigger: String
    public var readOutcome: String
    public var daysWritten: Int
    public var daysFailed: Int
    public var daysPending: Int
    public var errors: [String]

    public init(startedAt: Date, trigger: String, readOutcome: String, daysWritten: Int, daysFailed: Int, daysPending: Int, errors: [String]) {
        self.startedAt = startedAt
        self.trigger = trigger
        self.readOutcome = readOutcome
        self.daysWritten = daysWritten
        self.daysFailed = daysFailed
        self.daysPending = daysPending
        self.errors = errors
    }
}

extension LocalStore {
    static let sleepSourceSettingKey = "sleepSourcePreference"

    /// Stores (or, for nil, deletes) a (type, day) daily value and marks that dirty entry fresh, in one transaction.
    public func saveDailyValue(_ value: DailyValue?, type: HealthType, day: DayKey) throws {
        try dbQueue.write { db in
            if let value {
                try db.execute(sql: """
                    INSERT INTO dailyValue (type, day, value, deepHours, remHours, source) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(type, day) DO UPDATE SET
                        value = excluded.value, deepHours = excluded.deepHours,
                        remHours = excluded.remHours, source = excluded.source
                    """, arguments: [type.rawValue, day.description, value.value, value.deepHours, value.remHours, value.source])
            } else {
                try db.execute(sql: "DELETE FROM dailyValue WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
            }
            try db.execute(
                sql: "INSERT INTO dirty (type, day, fresh) VALUES (?, ?, 1) ON CONFLICT(type, day) DO UPDATE SET fresh = 1",
                arguments: [type.rawValue, day.description]
            )
        }
    }

    public func dailyValues(day: DayKey) throws -> [HealthType: DailyValue] {
        try dbQueue.read { db in
            var values: [HealthType: DailyValue] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM dailyValue WHERE day = ?", arguments: [day.description]) {
                let typeRaw: String = row["type"]
                guard let type = HealthType(rawValue: typeRaw) else {
                    throw LocalStoreError.corruptRow("dailyValue \(typeRaw) \(day)")
                }
                values[type] = DailyValue(value: row["value"], deepHours: row["deepHours"], remHours: row["remHours"], source: row["source"])
            }
            return values
        }
    }

    /// Marks an existing dirty entry not fresh, for a day whose daily-values query failed. Does nothing when there is no entry.
    public func markNotFresh(type: HealthType, day: DayKey) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE dirty SET fresh = 0 WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
        }
    }

    public func clearDirty(type: HealthType, day: DayKey) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dirty WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
        }
    }

    /// Clears the given (type, day) marks of one day, all or nothing, in a single transaction. Marks are deleted only when every one is still fresh: if any went stale again (a late sample after the caller read `dirtyEntries()`), nothing is deleted and every mark survives for the next run. Returns true only when all were deleted.
    @discardableResult
    public func clearDirty(day: DayKey, types: [HealthType]) throws -> Bool {
        try dbQueue.write { db in
            var freshCount = 0
            for type in types {
                freshCount += try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dirty WHERE type = ? AND day = ? AND fresh = 1", arguments: [type.rawValue, day.description]) ?? 0
            }
            guard freshCount == types.count else { return false }
            for type in types {
                try db.execute(sql: "DELETE FROM dirty WHERE type = ? AND day = ? AND fresh = 1", arguments: [type.rawValue, day.description])
            }
            return true
        }
    }

    /// "Rebuild all": every (type, day) that has stored samples becomes dirty and not fresh.
    public func markAllDirty() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dirty (type, day, fresh) SELECT DISTINCT type, day, 0 FROM sample WHERE true
                ON CONFLICT(type, day) DO UPDATE SET fresh = 0
                """)
            try Self.markEverySleepWakeDayDirty(db)
        }
    }

    /// Dirties the wake day of every stored sleep night, whichever source wins it. The stored-day marks of `markAllDirty` miss a night whose samples all start on the previous day.
    static func markEverySleepWakeDayDirty(_ db: Database) throws {
        let samples = try Row.fetchAll(db, sql: "SELECT * FROM sample WHERE type = ?", arguments: [HealthType.sleep.rawValue]).map(Self.sample(from:))
        // Every stored sample carries its own zone, so the fallback is never used.
        let seeds = Set(samples.map(\.uuid))
        let nights = SleepAggregator.affectedNights(in: samples, containing: seeds, fallback: TimeZone(identifier: "UTC")!)
        try markDirty(db, type: HealthType.sleep.rawValue, days: nights.wakeDays)
    }

    public func sleepSourcePreference() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT settingValue FROM setting WHERE settingKey = ?", arguments: [Self.sleepSourceSettingKey])
        }
    }

    public func setSleepSourcePreference(_ source: String?) throws {
        try dbQueue.write { db in
            let current = try String.fetchOne(db, sql: "SELECT settingValue FROM setting WHERE settingKey = ?", arguments: [Self.sleepSourceSettingKey])
            guard current != source else { return }
            if let source {
                try db.execute(
                    sql: "INSERT INTO setting (settingKey, settingValue) VALUES (?, ?) ON CONFLICT(settingKey) DO UPDATE SET settingValue = excluded.settingValue",
                    arguments: [Self.sleepSourceSettingKey, source]
                )
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE settingKey = ?", arguments: [Self.sleepSourceSettingKey])
            }
            // The choice decides which source's totals each night's note shows.
            try Self.markEverySleepWakeDayDirty(db)
        }
    }

    public func appendRun(_ record: RunRecord) throws {
        let errorsJSON = String(decoding: try JSONEncoder().encode(record.errors), as: UTF8.self)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO runRecord (startedAt, triggerName, readOutcome, daysWritten, daysFailed, daysPending, errors)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    record.startedAt.timeIntervalSince1970, record.trigger, record.readOutcome,
                    record.daysWritten, record.daysFailed, record.daysPending, errorsJSON,
                ])
        }
    }

    public func recentRuns(limit: Int) throws -> [RunRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM runRecord ORDER BY startedAt DESC, id DESC LIMIT ?", arguments: [limit]).map { row in
                let errorsText: String = row["errors"]
                let startedAt: Double = row["startedAt"]
                return RunRecord(
                    startedAt: Date(timeIntervalSince1970: startedAt),
                    trigger: row["triggerName"],
                    readOutcome: row["readOutcome"],
                    daysWritten: row["daysWritten"],
                    daysFailed: row["daysFailed"],
                    daysPending: row["daysPending"],
                    errors: try JSONDecoder().decode([String].self, from: Data(errorsText.utf8))
                )
            }
        }
    }

    /// Settings "Clear local copy": deletes the health data and anchors, so the next readable run re-reads everything from HealthKit.
    public func clearLocalCopy() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM sample;
                DELETE FROM anchor;
                DELETE FROM dirty;
                DELETE FROM dailyValue;
                """)
        }
    }
}
