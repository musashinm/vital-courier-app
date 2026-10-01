import Foundation

public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, timeZone: TimeZone) {
        let parts = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ text: String) {
        let fields = text.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              fields.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2])
        else { return nil }
        let utcZone = TimeZone(identifier: "UTC")!
        let calendar = Self.calendar(in: utcZone)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String { String(format: "%04ld-%02ld-%02ld", year, month, day) }

    public var monthKey: String { String(format: "%04ld-%02ld", year, month) }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> DayKey {
        let utcZone = TimeZone(identifier: "UTC")!
        let calendar = Self.calendar(in: utcZone)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return DayKey(date: calendar.date(byAdding: .day, value: days, to: start)!, timeZone: utcZone)
    }

    /// Local midnight to the next local midnight in `timeZone`.
    public func interval(in timeZone: TimeZone) -> DateInterval {
        let calendar = Self.calendar(in: timeZone)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Spec, Day assignment: a sample's day comes from its `HKMetadataKeyTimeZone`, else the phone's zone when the app first indexes it.
public enum DayAssigner {
    public static func zone(for sample: HealthSample, fallback: TimeZone) -> TimeZone {
        sample.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? fallback
    }

    public static func day(for sample: HealthSample, fallback: TimeZone) -> DayKey {
        DayKey(date: sample.start, timeZone: zone(for: sample, fallback: fallback))
    }

    /// The day a sleep sample ends on; a night belongs to its wake date.
    public static func wakeDay(for sample: HealthSample, fallback: TimeZone) -> DayKey {
        DayKey(date: sample.end, timeZone: zone(for: sample, fallback: fallback))
    }
}
