import Foundation
import GRDB

/// One day's cycle values (Cycle Tracking Spec, Storage). `flow` is nil when no flow was logged; the flags are false when nothing set them.
public struct CycleDay: Equatable, Sendable {
    public var flow: String?
    public var periodStart: Bool
    public var spotting: Bool

    public init(flow: String? = nil, periodStart: Bool = false, spotting: Bool = false) {
        self.flow = flow
        self.periodStart = periodStart
        self.spotting = spotting
    }
}

/// What one cycle type's daily-values pass found for a day. Each type owns its own columns of the shared row.
public enum CycleDayUpdate: Equatable, Sendable {
    case flow(String?, periodStart: Bool)
    case spotting(Bool)

    var type: HealthType {
        switch self {
        case .flow: .menstrualFlow
        case .spotting: .spotting
        }
    }
}

extension LocalStore {
    /// The cycle twin of `saveDailyValue`: updates the columns `update` owns, deletes the row once all three are empty, and marks that type's dirty entry fresh, in one transaction. A false flag is stored as NULL, so "empty" is one check.
    public func saveCycleDay(_ update: CycleDayUpdate, day: DayKey) throws {
        try write { db in
            try db.execute(sql: "INSERT INTO cycleDailyValue (day) VALUES (?) ON CONFLICT(day) DO NOTHING", arguments: [day.description])
            switch update {
            case .flow(let flow, let periodStart):
                let periodStartValue: Int? = periodStart ? 1 : nil
                try db.execute(sql: "UPDATE cycleDailyValue SET flow = ?, periodStart = ? WHERE day = ?", arguments: [flow, periodStartValue, day.description])
            case .spotting(let spotting):
                let spottingValue: Int? = spotting ? 1 : nil
                try db.execute(sql: "UPDATE cycleDailyValue SET spotting = ? WHERE day = ?", arguments: [spottingValue, day.description])
            }
            try db.execute(
                sql: "DELETE FROM cycleDailyValue WHERE day = ? AND flow IS NULL AND periodStart IS NULL AND spotting IS NULL",
                arguments: [day.description]
            )
            try db.execute(
                sql: "INSERT INTO dirty (type, day, fresh) VALUES (?, ?, 1) ON CONFLICT(type, day) DO UPDATE SET fresh = 1",
                arguments: [update.type.rawValue, day.description]
            )
        }
    }

    public func cycleDay(day: DayKey) throws -> CycleDay? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT flow, periodStart, spotting FROM cycleDailyValue WHERE day = ?", arguments: [day.description]) else {
                return nil
            }
            let periodStart: Int? = row["periodStart"]
            let spotting: Int? = row["spotting"]
            return CycleDay(flow: row["flow"], periodStart: periodStart == 1, spotting: spotting == 1)
        }
    }

    /// Cycle tracking turned off: drops the pending marks of `types`, so no later run writes them. Samples and daily rows stay.
    public func deleteDirtyMarks(types: [HealthType]) throws {
        try write { db in
            for type in types {
                try db.execute(sql: "DELETE FROM dirty WHERE type = ?", arguments: [type.rawValue])
            }
        }
    }
}
