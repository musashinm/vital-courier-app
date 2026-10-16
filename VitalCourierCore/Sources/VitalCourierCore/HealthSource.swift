import Foundation

public enum HealthSourceError: Error, Equatable {
    /// HealthKit refused the read (locked phone, or the odd background app-open case from the spike). Normal; retried on the next trigger.
    case readRefused
    /// The source said there was more to read but returned no new anchor, so reading again would loop forever.
    case anchorDidNotAdvance(HealthType)
}

/// A day's statistic in the type's statistic unit. `minimum` and `maximum` are set only for the average-minimum-maximum types, respiratory rate and blood glucose (Respiratory Rate Spec, Statistics query).
public struct DailyStatistic: Equatable, Sendable {
    public var value: Double
    public var minimum: Double?
    public var maximum: Double?

    public init(value: Double, minimum: Double? = nil, maximum: Double? = nil) {
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// Everything the core needs from HealthKit. The HealthKit-backed implementation lives in `VitalCourierHealthKit` (Task 8).
public protocol HealthSource: Sendable {
    /// True when protected data is available. A read can still be refused; that throws `readRefused`.
    func isReadable() async -> Bool
    /// Anchored query: one batch of samples and deletions since `anchor`, plus the new anchor. `hasMore` asks the caller to call again with that anchor.
    func changes(for type: HealthType, since anchor: Data?) async throws -> HealthChanges
    /// Every sample of `type` whose start is in `interval` (used by Verify).
    func samples(for type: HealthType, in interval: DateInterval) async throws -> [HealthSample]
    /// The earliest sample start across `types`; nil when there are none.
    func earliestSampleDate(types: [HealthType]) async throws -> Date?
    /// Sum types (steps: count, exercise: minutes) use `cumulativeSum`; resting heart rate uses `discreteAverage` (beats per minute); respiratory rate uses the average, minimum and maximum (breaths per minute). Nil when there is no data.
    func dailyStatistic(for type: HealthType, day: DayKey, timeZone: TimeZone) async throws -> DailyStatistic?
}
