import Foundation

/// One run (spec, Data flow): read, verify, daily values, write. Task 9 adds the write step.
public final class ExportRunner: Sendable {
    static let verifyWindow: TimeInterval = 30 * 24 * 60 * 60

    let store: LocalStore
    let health: any HealthSource
    let destination: @Sendable () -> (any ExportDestination)?
    let now: @Sendable () -> Date
    let timeZone: @Sendable () -> TimeZone

    public init(
        store: LocalStore,
        health: any HealthSource,
        destination: @escaping @Sendable () -> (any ExportDestination)?,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.store = store
        self.health = health
        self.destination = destination
        self.now = now
        self.timeZone = timeZone
    }

    /// `onReadCommitted` is called exactly once, right after the read step, whether it read, was skipped or failed. The HealthKit observer completion handler goes here, never after file writes.
    public func run(trigger: Trigger, options: RunOptions, onReadCommitted: @escaping @Sendable () -> Void) async -> RunOutcome {
        let zone = timeZone()
        var errors: [String] = []
        var readOutcome = ReadOutcome.notRequested
        // Rebuild all marks every stored day dirty first, so it works even while HealthKit is locked.
        if options.markAllDirty {
            do {
                try store.markAllDirty()
            } catch {
                errors.append("rebuild: \(error)")
            }
        }
        if options.read {
            if await health.isReadable() {
                readOutcome = await readStep(options: options, zone: zone, errors: &errors)
            } else {
                readOutcome = .skippedLocked
            }
        }
        onReadCommitted()
        if readOutcome == .read {
            await verifyStep(scope: options.verify, zone: zone, errors: &errors)
            await dailyValuesStep(zone: zone, errors: &errors)
        }
        return RunOutcome(readOutcome: readOutcome, daysWritten: 0, daysFailed: 0, daysPending: 0, errors: errors)
    }

    func readStep(options: RunOptions, zone: TimeZone, errors: inout [String]) async -> ReadOutcome {
        do {
            for type in HealthType.allCases {
                let changes = try await health.changes(for: type, since: try store.anchor(for: type))
                try store.applyChanges(changes, for: type, fallbackTimeZone: zone)
            }
            return .read
        } catch HealthSourceError.readRefused {
            return .skippedLocked
        } catch {
            errors.append("read: \(error)")
            return .failed
        }
    }

    /// Catches deletions HealthKit dropped before the app saw them, within the scope only.
    func verifyStep(scope: VerifyScope, zone: TimeZone, errors: inout [String]) async {
        let end = now()
        let start: Date
        do {
            switch scope {
            case .none: return
            case .last30Days: start = end.addingTimeInterval(-Self.verifyWindow)
            case .allDates: start = try await health.earliestSampleDate() ?? end
            }
        } catch {
            errors.append("verify: \(error)")
            return
        }
        let interval = DateInterval(start: start, end: end)
        for type in HealthType.allCases {
            do {
                let remote = try await health.samples(for: type, in: interval)
                let remoteUUIDs = Set(remote.map(\.uuid))
                let localUUIDs = try store.sampleUUIDs(type: type, startingIn: interval)
                let missing = remote.filter { !localUUIDs.contains($0.uuid) }
                let removed = localUUIDs.subtracting(remoteUUIDs)
                if missing.isEmpty && removed.isEmpty { continue }
                try store.applyChanges(HealthChanges(added: missing, deletedUUIDs: Array(removed)), for: type, fallbackTimeZone: zone)
            } catch {
                errors.append("verify \(type.rawValue): \(error)")
            }
        }
    }

    /// Runs after Verify, so stored values never lag behind samples Verify added or removed.
    func dailyValuesStep(zone: TimeZone, errors: inout [String]) async {
        let staleEntries: [DirtyEntry]
        let preferredSleepSource: String?
        do {
            staleEntries = try store.dirtyEntries().filter { !$0.fresh }
            preferredSleepSource = try store.sleepSourcePreference()
        } catch {
            errors.append("daily values: \(error)")
            return
        }
        for entry in staleEntries {
            do {
                let value = try await dailyValue(for: entry, zone: zone, preferredSleepSource: preferredSleepSource)
                try store.saveDailyValue(value, type: entry.type, day: entry.day)
            } catch {
                errors.append("daily values \(entry.type.rawValue) \(entry.day): \(error)")
            }
        }
    }

    func dailyValue(for entry: DirtyEntry, zone: TimeZone, preferredSleepSource: String?) async throws -> DailyValue? {
        switch entry.type {
        case .steps, .restingHeartRate:
            return try await health.dailyStatistic(for: entry.type, day: entry.day, timeZone: zone).map { DailyValue(value: $0) }
        case .weight:
            let latest = try store.samples(type: .weight, fromDay: entry.day, toDay: entry.day).max { $0.end < $1.end }
            guard let latest, case .quantity(let kilograms) = latest.value else { return nil }
            return DailyValue(value: kilograms)
        case .sleep:
            let samples = try store.samples(type: .sleep, fromDay: entry.day.adding(days: -1), toDay: entry.day)
            let nights = SleepAggregator.nights(from: samples, preferredSource: preferredSleepSource, fallback: zone)
            guard let night = nights[entry.day] else { return nil }
            return DailyValue(value: night.asleepHours, deepHours: night.deepHours, remHours: night.remHours, source: night.source)
        }
    }
}
