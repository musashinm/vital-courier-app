import Foundation
import GRDB

public struct DailyValue: Equatable, Sendable {
    /// Steps: count. Exercise: minutes. Resting heart rate: beats per minute. Walking heart rate average: beats per minute. Heart rate: beats per minute (the day's average). Respiratory rate: breaths per minute (the day's average). Blood glucose: mg/dL (the day's average). Weight: kg. Sleep: asleep hours.
    public var value: Double
    public var deepHours: Double?
    public var remHours: Double?
    /// Sleep only: the source the night's totals came from.
    public var source: String?
    /// Heart rate, respiratory rate and blood glucose only: the day's lowest and highest reading, in the same unit as `value`.
    public var minimum: Double?
    public var maximum: Double?

    public init(value: Double, deepHours: Double? = nil, remHours: Double? = nil, source: String? = nil, minimum: Double? = nil, maximum: Double? = nil) {
        self.value = value
        self.deepHours = deepHours
        self.remHours = remHours
        self.source = source
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct RunRecord: Equatable, Sendable {
    /// The `runRecord` row id; nil until the record is saved. History pages by it.
    public var id: Int64?
    public var startedAt: Date
    public var trigger: String
    public var readOutcome: String
    public var daysWritten: Int
    public var daysFailed: Int
    public var daysPending: Int
    public var errors: [String]

    public init(startedAt: Date, trigger: String, readOutcome: String, daysWritten: Int, daysFailed: Int, daysPending: Int, errors: [String], id: Int64? = nil) {
        self.id = id
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
        try write { db in
            if let value {
                try db.execute(sql: """
                    INSERT INTO dailyValue (type, day, value, deepHours, remHours, source, minValue, maxValue) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(type, day) DO UPDATE SET
                        value = excluded.value, deepHours = excluded.deepHours,
                        remHours = excluded.remHours, source = excluded.source,
                        minValue = excluded.minValue, maxValue = excluded.maxValue
                    """, arguments: [type.rawValue, day.description, value.value, value.deepHours, value.remHours, value.source, value.minimum, value.maximum])
            } else {
                try db.execute(sql: "DELETE FROM dailyValue WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
            }
            try db.execute(
                sql: "INSERT INTO dirty (type, day, fresh) VALUES (?, ?, 1) ON CONFLICT(type, day) DO UPDATE SET fresh = 1",
                arguments: [type.rawValue, day.description]
            )
        }
    }

    /// Stored sleep samples in `from...to`, widened until every night in the result is whole.
    func sleepSamples(from: Date, to: Date) throws -> [HealthSample] {
        try dbQueue.read { db in try Self.sleepSamples(db, from: from, to: to) }
    }

    public func dailyValues(day: DayKey) throws -> [HealthType: DailyValue] {
        try dbQueue.read { db in
            var values: [HealthType: DailyValue] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM dailyValue WHERE day = ?", arguments: [day.description]) {
                let typeRaw: String = row["type"]
                guard let type = HealthType(rawValue: typeRaw) else {
                    throw LocalStoreError.corruptRow("dailyValue \(typeRaw) \(day)")
                }
                values[type] = DailyValue(value: row["value"], deepHours: row["deepHours"], remHours: row["remHours"], source: row["source"], minimum: row["minValue"], maximum: row["maxValue"])
            }
            return values
        }
    }

    /// Marks an existing dirty entry not fresh, for a day whose daily-values query failed. Does nothing when there is no entry.
    public func markNotFresh(type: HealthType, day: DayKey) throws {
        try write { db in
            try db.execute(sql: "UPDATE dirty SET fresh = 0 WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
        }
    }

    public func clearDirty(type: HealthType, day: DayKey) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM dirty WHERE type = ? AND day = ?", arguments: [type.rawValue, day.description])
        }
    }

    /// Clears the given (type, day) marks of one day, all or nothing, in a single transaction. Marks are deleted only when every one is still fresh: if any went stale again (a late sample after the caller read `dirtyEntries()`), nothing is deleted and every mark survives for the next run. Returns true only when all were deleted.
    @discardableResult
    public func clearDirty(day: DayKey, types: [HealthType]) throws -> Bool {
        try write { db in
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

    /// "Rebuild all": every (type, day) of `types` that has stored samples becomes dirty and not fresh. `statisticsZone` is the zone the daily statistics are queried in. The runner passes the enabled types, so a switched-off type is never rebuilt.
    public func markAllDirty(statisticsZone: TimeZone, types: [HealthType] = HealthType.allCases) throws {
        let typeNames = types.map(\.rawValue)
        try write { db in
            try db.execute(sql: """
                INSERT INTO dirty (type, day, fresh) SELECT DISTINCT type, day, 0 FROM sample WHERE type IN (\(databaseQuestionMarks(count: typeNames.count)))
                ON CONFLICT(type, day) DO UPDATE SET fresh = 0
                """, arguments: StatementArguments(typeNames))
            if types.contains(.sleep) {
                try Self.markEverySleepWakeDayDirty(db)
            }
            try Self.markEveryOverlappedDayDirty(db, statisticsZone: statisticsZone, types: types)
        }
    }

    /// Dirties every day each stored sample of a statistics type (`HealthType.usesStatisticsQuery`) in `types` overlaps, in its stored zone and in `statisticsZone`. The stored-day marks of `markAllDirty` miss the later days of a sample that crosses midnight.
    static func markEveryOverlappedDayDirty(_ db: Database, statisticsZone: TimeZone, types: [HealthType]) throws {
        let statisticsTypeNames = types.filter(\.usesStatisticsQuery).map(\.rawValue)
        guard !statisticsTypeNames.isEmpty else { return }
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT type, zone, startTime, endTime FROM sample WHERE type IN (\(databaseQuestionMarks(count: statisticsTypeNames.count)))",
            arguments: StatementArguments(statisticsTypeNames)
        )
        for row in rows {
            let typeRaw: String = row["type"]
            let zoneIdentifier: String = row["zone"]
            let startTime: Double = row["startTime"]
            let endTime: Double = row["endTime"]
            let storedZone = TimeZone(identifier: zoneIdentifier) ?? statisticsZone
            let start = Date(timeIntervalSince1970: startTime)
            let end = Date(timeIntervalSince1970: endTime)
            let days = overlappedDays(start: start, end: end, zone: storedZone).union(overlappedDays(start: start, end: end, zone: statisticsZone))
            try markDirty(db, type: typeRaw, days: days)
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
        try write { db in
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
        try write { db in
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
        try dbQueue.read { db in try Self.runs(db, before: nil, limit: limit) }
    }

    static func runRecord(from row: Row) throws -> RunRecord {
        let errorsText: String = row["errors"]
        let startedAt: Double = row["startedAt"]
        return RunRecord(
            startedAt: Date(timeIntervalSince1970: startedAt),
            trigger: row["triggerName"],
            readOutcome: row["readOutcome"],
            daysWritten: row["daysWritten"],
            daysFailed: row["daysFailed"],
            daysPending: row["daysPending"],
            errors: try JSONDecoder().decode([String].self, from: Data(errorsText.utf8)),
            id: row["id"]
        )
    }

    /// Settings "Clear local copy": deletes the health data and anchors, so the next readable run re-reads everything from HealthKit.
    public func clearLocalCopy() throws {
        try write { db in
            try db.execute(sql: """
                DELETE FROM sample;
                DELETE FROM anchor;
                DELETE FROM dirty;
                DELETE FROM dailyValue;
                DELETE FROM cycleDailyValue;
                """)
        }
    }
}

extension RunRecord {
    /// Stored trigger name of a record that no run produced: a protection failure after a store write, or an observer acknowledgement timeout. History labels it "App event".
    public static let appEventTrigger = "appEvent"
    public static let fileProtectionErrorPrefix = "file protection: "
    public static let observerAcknowledgementErrorPrefix = "observer acknowledgement: "
}

extension LocalStore {
    /// Saves a run-history row for something that happened outside a run, so History and the Run detail show it.
    public func recordAppEvent(errors: [String], at startedAt: Date) throws {
        try appendRun(RunRecord(startedAt: startedAt, trigger: RunRecord.appEventTrigger, readOutcome: ReadOutcome.notRequested.rawValue, daysWritten: 0, daysFailed: 0, daysPending: 0, errors: errors))
    }

    /// Writes any pending protection failures to run history. Called when the store opens and after every write that is not a run (a run adds them to its own record): the sleep source choice, Clear local copy, and the record written by the previous call. The queue is only emptied after the row is saved, so a throw leaves it pending; a protection failure while writing the row itself is appended behind them and stays pending for the next call or launch.
    public func recordProtectionFailuresInHistory(at startedAt: Date) throws {
        try drainPendingProtectionFailures { failures in
            guard !failures.isEmpty else { return nil }
            return RunRecord(startedAt: startedAt, trigger: RunRecord.appEventTrigger, readOutcome: ReadOutcome.notRequested.rawValue, daysWritten: 0, daysFailed: 0, daysPending: 0, errors: failures.map { RunRecord.fileProtectionErrorPrefix + $0 })
        }
    }
}
