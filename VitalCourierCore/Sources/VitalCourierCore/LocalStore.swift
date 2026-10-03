import Foundation
import GRDB

public enum LocalStoreError: Error, Equatable {
    case corruptRow(String)
    /// A History page cursor that was never saved, so it has no row id.
    case invalidCursor
}

public struct DirtyEntry: Hashable, Sendable {
    public let type: HealthType
    public let day: DayKey
    public let fresh: Bool

    public init(type: HealthType, day: DayKey, fresh: Bool) {
        self.type = type
        self.day = day
        self.fresh = fresh
    }
}

/// The app's own database (spec, Units: LocalStore). Holds a full copy of every sample so files can be rebuilt while the phone is locked.
public final class LocalStore: Sendable {
    static let fileName = "local-store.sqlite"

    let dbQueue: DatabaseQueue

    public static func inMemory() throws -> LocalStore {
        try LocalStore(dbQueue: DatabaseQueue())
    }

    /// Opens or creates the store in `directory`. The directory and the database get `completeUntilFirstUserAuthentication` protection, so new journal and temp files inherit it, and the directory is excluded from backup.
    public static func open(directory: URL) throws -> LocalStore {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        var backupExcluded = URLResourceValues()
        backupExcluded.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(backupExcluded)

        let databasePath = directory.appendingPathComponent(fileName).path
        let store = try LocalStore(dbQueue: DatabaseQueue(path: databasePath))
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databasePath
        )
        #endif
        return store
    }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE sample (
                    uuid TEXT PRIMARY KEY NOT NULL,
                    type TEXT NOT NULL,
                    startTime REAL NOT NULL,
                    endTime REAL NOT NULL,
                    valueNumber REAL,
                    valueText TEXT,
                    source TEXT NOT NULL,
                    device TEXT,
                    metadata TEXT NOT NULL,
                    zone TEXT NOT NULL,
                    day TEXT NOT NULL,
                    month TEXT NOT NULL
                );
                CREATE INDEX sample_type_month ON sample(type, month);
                CREATE INDEX sample_type_day ON sample(type, day);
                CREATE INDEX sample_type_start ON sample(type, startTime);
                CREATE TABLE anchor (
                    type TEXT PRIMARY KEY NOT NULL,
                    data BLOB NOT NULL
                );
                CREATE TABLE dirty (
                    type TEXT NOT NULL,
                    day TEXT NOT NULL,
                    fresh INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (type, day)
                );
                CREATE TABLE dailyValue (
                    type TEXT NOT NULL,
                    day TEXT NOT NULL,
                    value REAL NOT NULL,
                    deepHours REAL,
                    remHours REAL,
                    source TEXT,
                    PRIMARY KEY (type, day)
                );
                CREATE TABLE setting (
                    settingKey TEXT PRIMARY KEY NOT NULL,
                    settingValue TEXT NOT NULL
                );
                CREATE TABLE runRecord (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    startedAt REAL NOT NULL,
                    triggerName TEXT NOT NULL,
                    readOutcome TEXT NOT NULL,
                    daysWritten INTEGER NOT NULL,
                    daysFailed INTEGER NOT NULL,
                    daysPending INTEGER NOT NULL,
                    errors TEXT NOT NULL
                );
                """)
        }
        return migrator
    }

    public func anchor(for type: HealthType) throws -> Data? {
        try dbQueue.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM anchor WHERE type = ?", arguments: [type.rawValue])
        }
    }

    /// One transaction (spec, Data flow step 1.2): new samples get their day once, deleted UUIDs lose their row, every touched (type, day) is marked dirty and not fresh, and the anchor is saved when there is one.
    public func applyChanges(_ changes: HealthChanges, for type: HealthType, fallbackTimeZone: TimeZone) throws {
        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.sortedKeys]
        try dbQueue.write { db in
            for sample in changes.added {
                // A sleep sample can merge nights, so the wake days of its nights are collected from the stored samples before the write.
                let sleepWakeDays = sample.type == .sleep ? try Self.sleepWakeDaysAffected(db, uuid: sample.uuid, incoming: sample, fallbackTimeZone: fallbackTimeZone) : []
                let zone = DayAssigner.zone(for: sample, fallback: fallbackTimeZone)
                let sampleDay = DayKey(date: sample.start, timeZone: zone)
                let metadata = String(decoding: try metadataEncoder.encode(sample.metadata), as: UTF8.self)
                var valueNumber: Double?
                var valueText: String?
                switch sample.value {
                case .quantity(let number): valueNumber = number
                case .category(let text): valueText = text
                }
                // On conflict the stored zone, day and month stay: a day is computed once (spec, Day assignment).
                try db.execute(sql: """
                    INSERT INTO sample (uuid, type, startTime, endTime, valueNumber, valueText, source, device, metadata, zone, day, month)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(uuid) DO UPDATE SET
                        startTime = excluded.startTime,
                        endTime = excluded.endTime,
                        valueNumber = excluded.valueNumber,
                        valueText = excluded.valueText,
                        source = excluded.source,
                        device = excluded.device,
                        metadata = excluded.metadata
                    """, arguments: [
                        sample.uuid.uuidString, sample.type.rawValue,
                        sample.start.timeIntervalSince1970, sample.end.timeIntervalSince1970,
                        valueNumber, valueText, sample.source, sample.device, metadata,
                        zone.identifier, sampleDay.description, sampleDay.monthKey,
                    ])
                try Self.markTouched(db, uuid: sample.uuid, fallbackTimeZone: fallbackTimeZone)
                try Self.markDirty(db, type: HealthType.sleep.rawValue, days: sleepWakeDays)
            }
            for uuid in changes.deletedUUIDs {
                let sleepWakeDays = try Self.sleepWakeDaysAffected(db, uuid: uuid, incoming: nil, fallbackTimeZone: fallbackTimeZone)
                try Self.markTouched(db, uuid: uuid, fallbackTimeZone: fallbackTimeZone)
                try db.execute(sql: "DELETE FROM sample WHERE uuid = ?", arguments: [uuid.uuidString])
                // The deletion can split a night, so the pieces' wake days are dirtied too.
                try Self.markDirty(db, type: HealthType.sleep.rawValue, days: sleepWakeDays)
            }
            if let anchor = changes.newAnchor {
                try db.execute(
                    sql: "INSERT INTO anchor (type, data) VALUES (?, ?) ON CONFLICT(type) DO UPDATE SET data = excluded.data",
                    arguments: [type.rawValue, anchor]
                )
            }
        }
    }

    /// Marks the stored day of a sample dirty and, for sleep, its wake day too. Does nothing for an unknown UUID.
    static func markTouched(_ db: Database, uuid: UUID, fallbackTimeZone: TimeZone) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT type, day, zone, endTime FROM sample WHERE uuid = ?",
            arguments: [uuid.uuidString]
        ) else { return }
        let typeRaw: String = row["type"]
        let storedDay: String = row["day"]
        try markDirty(db, type: typeRaw, day: storedDay)
        if typeRaw == HealthType.sleep.rawValue {
            let zoneIdentifier: String = row["zone"]
            let endTime: Double = row["endTime"]
            let zone = TimeZone(identifier: zoneIdentifier) ?? fallbackTimeZone
            let wakeDay = DayKey(date: Date(timeIntervalSince1970: endTime), timeZone: zone)
            try markDirty(db, type: typeRaw, day: wakeDay.description)
        }
    }

    /// Every stored sleep sample in whole nights around `from...to`: the range is widened by the night gap and then again around whatever that finds, until it stops growing. It ends on its own: the range only widens when a stored asleep sample reaches past it, and the store holds finitely many samples. There is deliberately no cap, because a capped search would return a truncated night as if it were complete.
    static func sleepSamples(_ db: Database, from seedStart: Date, to seedEnd: Date) throws -> [HealthSample] {
        let gap = SleepAggregator.nightGap
        var lower = seedStart.addingTimeInterval(-gap)
        var upper = seedEnd.addingTimeInterval(gap)
        while true {
            let samples = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sample WHERE type = ? AND startTime <= ? AND endTime >= ? ORDER BY startTime, uuid",
                arguments: [HealthType.sleep.rawValue, upper.timeIntervalSince1970, lower.timeIntervalSince1970]
            ).map(Self.sample(from:))
            let asleep = samples.filter(SleepAggregator.isAsleep)
            let widenedLower = asleep.map(\.start).min().map { min(lower, $0.addingTimeInterval(-gap)) } ?? lower
            let widenedUpper = asleep.map(\.end).max().map { max(upper, $0.addingTimeInterval(gap)) } ?? upper
            if widenedLower == lower && widenedUpper == upper { return samples }
            lower = widenedLower
            upper = widenedUpper
        }
    }

    static func sleepWakeDaysAffected(_ db: Database, uuid: UUID, incoming: HealthSample?, fallbackTimeZone: TimeZone) throws -> Set<DayKey> {
        var rangeStart = incoming?.start
        var rangeEnd = incoming?.end
        if let row = try Row.fetchOne(db, sql: "SELECT type, startTime, endTime FROM sample WHERE uuid = ?", arguments: [uuid.uuidString]) {
            let typeRaw: String = row["type"]
            guard typeRaw == HealthType.sleep.rawValue else { return [] }
            let startTime: Double = row["startTime"]
            let endTime: Double = row["endTime"]
            rangeStart = min(rangeStart ?? .distantFuture, Date(timeIntervalSince1970: startTime))
            rangeEnd = max(rangeEnd ?? .distantPast, Date(timeIntervalSince1970: endTime))
        }
        guard let rangeStart, let rangeEnd else { return [] }
        let stored = try sleepSamples(db, from: rangeStart, to: rangeEnd)
        return SleepAggregator.wakeDaysAffected(stored: stored, replacing: uuid, with: incoming, fallback: fallbackTimeZone)
    }

    static func markDirty(_ db: Database, type: String, days: Set<DayKey>) throws {
        for day in days { try markDirty(db, type: type, day: day.description) }
    }

    static func markDirty(_ db: Database, type: String, day: String) throws {
        try db.execute(
            sql: "INSERT INTO dirty (type, day, fresh) VALUES (?, ?, 0) ON CONFLICT(type, day) DO UPDATE SET fresh = 0",
            arguments: [type, day]
        )
    }

    public func dirtyEntries() throws -> [DirtyEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT type, day, fresh FROM dirty ORDER BY day, type").map { row in
                let typeRaw: String = row["type"]
                let dayText: String = row["day"]
                guard let type = HealthType(rawValue: typeRaw), let day = DayKey(dayText) else {
                    throw LocalStoreError.corruptRow("dirty \(typeRaw) \(dayText)")
                }
                return DirtyEntry(type: type, day: day, fresh: row["fresh"])
            }
        }
    }

    public func samples(type: HealthType, month monthKey: String) throws -> [HealthSample] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM sample WHERE type = ? AND month = ? ORDER BY startTime, uuid",
                arguments: [type.rawValue, monthKey]
            ).map(Self.sample(from:))
        }
    }

    public func samples(type: HealthType, fromDay: DayKey, toDay: DayKey) throws -> [HealthSample] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM sample WHERE type = ? AND day >= ? AND day <= ? ORDER BY startTime, uuid",
                arguments: [type.rawValue, fromDay.description, toDay.description]
            ).map(Self.sample(from:))
        }
    }

    public func sampleUUIDs(type: HealthType, startingIn interval: DateInterval) throws -> Set<UUID> {
        try dbQueue.read { db in
            let texts = try String.fetchAll(
                db,
                sql: "SELECT uuid FROM sample WHERE type = ? AND startTime >= ? AND startTime < ?",
                arguments: [type.rawValue, interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970]
            )
            return Set(try texts.map { text in
                guard let uuid = UUID(uuidString: text) else { throw LocalStoreError.corruptRow("sample uuid \(text)") }
                return uuid
            })
        }
    }

    /// Start of the earliest stored sample across all types; nil when the store has none.
    func earliestSampleStart() throws -> Date? {
        try dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT MIN(startTime) FROM sample").map { Date(timeIntervalSince1970: $0) }
        }
    }

    static func sample(from row: Row) throws -> HealthSample {
        let uuidText: String = row["uuid"]
        let typeRaw: String = row["type"]
        guard let uuid = UUID(uuidString: uuidText), let type = HealthType(rawValue: typeRaw) else {
            throw LocalStoreError.corruptRow("sample \(uuidText)")
        }
        let valueNumber: Double? = row["valueNumber"]
        let valueText: String? = row["valueText"]
        let value: SampleValue
        if let valueNumber {
            value = .quantity(valueNumber)
        } else if let valueText {
            value = .category(valueText)
        } else {
            throw LocalStoreError.corruptRow("sample \(uuidText) has no value")
        }
        let metadataText: String = row["metadata"]
        let metadata = try JSONDecoder().decode([String: String].self, from: Data(metadataText.utf8))
        let startTime: Double = row["startTime"]
        let endTime: Double = row["endTime"]
        return HealthSample(
            uuid: uuid,
            type: type,
            start: Date(timeIntervalSince1970: startTime),
            end: Date(timeIntervalSince1970: endTime),
            value: value,
            source: row["source"],
            device: row["device"],
            metadata: metadata,
            timeZoneIdentifier: row["zone"]
        )
    }
}
