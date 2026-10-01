import Foundation

public enum HealthSourceError: Error, Equatable {
    /// HealthKit refused the read (locked phone, or the odd background app-open case from the spike). Normal; retried on the next trigger.
    case readRefused
}

/// Everything the core needs from HealthKit. The HealthKit-backed implementation lives in the app target (second plan).
public protocol HealthSource: Sendable {
    /// True when protected data is available. A read can still be refused; that throws `readRefused`.
    func isReadable() async -> Bool
    /// Anchored query: samples and deletions since `anchor`, plus the new anchor.
    func changes(for type: HealthType, since anchor: Data?) async throws -> HealthChanges
    /// Every sample of `type` whose start is in `interval` (used by Verify).
    func samples(for type: HealthType, in interval: DateInterval) async throws -> [HealthSample]
    /// The earliest sample start across the four types; nil when there are none.
    func earliestSampleDate() async throws -> Date?
    /// Steps: `cumulativeSum` (count). Resting heart rate: `discreteAverage` (beats per minute). Nil when there is no data.
    func dailyStatistic(for type: HealthType, day: DayKey, timeZone: TimeZone) async throws -> Double?
}
