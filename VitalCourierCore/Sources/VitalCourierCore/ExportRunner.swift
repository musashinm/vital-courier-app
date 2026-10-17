import Foundation

/// One run (spec, Data flow): read, verify, daily values, write.
public final class ExportRunner: Sendable {
    static let verifyWindow: TimeInterval = 30 * 24 * 60 * 60

    let store: LocalStore
    let health: any HealthSource
    let destination: @Sendable () -> (any ExportDestination)?
    let now: @Sendable () -> Date
    let timeZone: @Sendable () -> TimeZone
    let enabledTypes: @Sendable () -> [HealthType]
    /// The enabled types HealthKit has already been asked about. Only these are queried; the rest wait in the store (Exercise Minutes Spec, Launch read).
    let readableTypes: @Sendable () -> [HealthType]

    public init(
        store: LocalStore,
        health: any HealthSource,
        destination: @escaping @Sendable () -> (any ExportDestination)?,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        enabledTypes: @escaping @Sendable () -> [HealthType] = { HealthType.baseTypes },
        readableTypes: (@Sendable () -> [HealthType])? = nil
    ) {
        self.store = store
        self.health = health
        self.destination = destination
        self.now = now
        self.timeZone = timeZone
        self.enabledTypes = enabledTypes
        self.readableTypes = readableTypes ?? enabledTypes
    }

    /// `onReadCommitted` is called exactly once, right after the read step, whether it read, was skipped or failed. The HealthKit observer completion handler goes here, never after file writes.
    public func run(trigger: Trigger, options: RunOptions, onReadCommitted: @escaping @Sendable () -> Void) async -> RunOutcome {
        let startedAt = now()
        let zone = timeZone()
        // Read once, so the switch can't change mid-run between steps.
        let types = enabledTypes()
        let readable = readableTypes().filter(types.contains)
        var errors: [String] = []
        var readOutcome = ReadOutcome.notRequested
        // Rebuild all marks every stored day dirty first, so it works even while HealthKit is locked.
        if options.markAllDirty {
            do {
                try store.markAllDirty(statisticsZone: zone, types: types)
            } catch {
                errors.append("rebuild: \(error)")
            }
        }
        if options.read {
            if await health.isReadable() {
                readOutcome = await readStep(types: readable, zone: zone, errors: &errors)
            } else {
                readOutcome = .skippedLocked
            }
        }
        onReadCommitted()
        // HealthKit was readable for this run, even when one type's read failed part way.
        if readOutcome == .read || readOutcome == .failed {
            await verifyStep(scope: options.verify, types: readable, zone: zone, errors: &errors)
            await dailyValuesStep(types: types, readable: readable, zone: zone, errors: &errors)
        }
        let counts = writeStep(types: types, zone: zone, errors: &errors)
        do {
            // Snapshot, history row and discard of the pending protection failures happen as one serialized drain.
            try store.drainPendingProtectionFailures { pendingFailures in
                errors.append(contentsOf: pendingFailures.map { RunRecord.fileProtectionErrorPrefix + $0 })
                return RunRecord(
                    startedAt: startedAt,
                    trigger: trigger.rawValue,
                    readOutcome: readOutcome.rawValue,
                    daysWritten: counts.written,
                    daysFailed: counts.failed,
                    daysPending: counts.pending,
                    errors: errors
                )
            }
        } catch {
            errors.append("run history: \(error)")
        }
        return RunOutcome(readOutcome: readOutcome, daysWritten: counts.written, daysFailed: counts.failed, daysPending: counts.pending, errors: errors)
    }

    func readStep(types: [HealthType], zone: TimeZone, errors: inout [String]) async -> ReadOutcome {
        do {
            for type in types {
                var hasMore = true
                while hasMore {
                    if Task.isCancelled { return .read }
                    let anchor = try store.anchor(for: type)
                    let changes = try await health.changes(for: type, since: anchor)
                    if changes.hasMore && (changes.newAnchor == nil || changes.newAnchor == anchor) {
                        throw HealthSourceError.anchorDidNotAdvance(type)
                    }
                    // Each batch commits with its anchor (spec, Data flow 1.2), so an expired run keeps what it read.
                    try store.applyChanges(changes, for: type, fallbackTimeZone: zone)
                    hasMore = changes.hasMore
                }
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
    func verifyStep(scope: VerifyScope, types: [HealthType], zone: TimeZone, errors: inout [String]) async {
        let end = now()
        let start: Date
        do {
            switch scope {
            case .none: return
            case .last30Days: start = end.addingTimeInterval(-Self.verifyWindow)
            case .allDates:
                // Also reach back to the earliest local sample, so samples older than HealthKit's earliest (or all of them, when HealthKit is empty) are compared.
                let earliest = [try await health.earliestSampleDate(types: types), try store.earliestSampleStart(types: types)].compactMap { $0 }.min()
                guard let earliest else { return }
                start = earliest
            }
        } catch {
            errors.append("verify: \(error)")
            return
        }
        let windows = Self.verifyWindows(from: start, to: end, splitByMonth: scope == .allDates, zone: zone)
        for type in types {
            for window in windows {
                // Between windows, so a cancelled run stops without loading another month.
                if Task.isCancelled { return }
                do {
                    let remote = try await health.samples(for: type, in: window)
                    let remoteUUIDs = Set(remote.map(\.uuid))
                    let localUUIDs = try store.sampleUUIDs(type: type, startingIn: window)
                    let missing = remote.filter { !localUUIDs.contains($0.uuid) }
                    let removed = localUUIDs.subtracting(remoteUUIDs)
                    if missing.isEmpty && removed.isEmpty { continue }
                    try store.applyChanges(HealthChanges(added: missing, deletedUUIDs: Array(removed)), for: type, fallbackTimeZone: zone)
                } catch {
                    errors.append("verify \(type.rawValue): \(error)")
                }
            }
        }
    }

    /// One window, or one per local calendar month for a years-long history, so no query loads it all at once. Windows are half-open on the start time and contiguous, so each sample is compared once. Boundaries come from the calendar, never from adding a month to `start`.
    private static func verifyWindows(from start: Date, to end: Date, splitByMonth: Bool, zone: TimeZone) -> [DateInterval] {
        guard splitByMonth else { return [DateInterval(start: start, end: end)] }
        let calendar = DayKey.calendar(in: zone)
        var windows: [DateInterval] = []
        var windowStart = start
        while windowStart < end {
            guard let monthStart = calendar.dateInterval(of: .month, for: windowStart)?.start,
                  let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  nextMonthStart < end else {
                windows.append(DateInterval(start: windowStart, end: end))
                break
            }
            windows.append(DateInterval(start: windowStart, end: nextMonthStart))
            windowStart = nextMonthStart
        }
        return windows
    }

    /// Runs after Verify, so stored values never lag behind samples Verify added or removed. Entries of a type that isn't enabled are left alone.
    func dailyValuesStep(types: [HealthType], readable: [HealthType], zone: TimeZone, errors: inout [String]) async {
        let enabled = Set(types)
        let dirtyEntries: [DirtyEntry]
        let preferredSleepSource: String?
        do {
            dirtyEntries = try store.dirtyEntries().filter { enabled.contains($0.type) }
            preferredSleepSource = try store.sleepSourcePreference()
        } catch {
            errors.append("daily values: \(error)")
            return
        }
        // Every dirty entry, fresh or not: a day left dirty by a skipped or failed write must not keep stale values.
        for entry in dirtyEntries {
            if Task.isCancelled { return }
            // A statistics type HealthKit hasn't been asked about can't be queried yet; its day stays dirty for a later run.
            if entry.type.usesStatisticsQuery && !readable.contains(entry.type) {
                // An earlier run may have left this mark fresh after a failed write. Without this, writeStep would write the old stored value and clear the day's marks.
                do {
                    try store.markNotFresh(type: entry.type, day: entry.day)
                } catch {
                    errors.append("daily values \(entry.type.rawValue) \(entry.day) invalidate: \(error)")
                }
                continue
            }
            do {
                if HealthType.cycleTypes.contains(entry.type) {
                    try store.saveCycleDay(try cycleDayUpdate(for: entry), day: entry.day)
                } else {
                    let value = try await dailyValue(for: entry, zone: zone, preferredSleepSource: preferredSleepSource)
                    try store.saveDailyValue(value, type: entry.type, day: entry.day)
                }
            } catch {
                errors.append("daily values \(entry.type.rawValue) \(entry.day): \(error)")
                // A value fresh from an earlier run must not be written as if it were current.
                do {
                    try store.markNotFresh(type: entry.type, day: entry.day)
                } catch {
                    errors.append("daily values \(entry.type.rawValue) \(entry.day) invalidate: \(error)")
                }
            }
        }
    }

    /// A cycle sample counts on its stored start day only (Cycle Tracking Spec, Day assignment).
    func cycleDayUpdate(for entry: DirtyEntry) throws -> CycleDayUpdate {
        let samples = try store.samples(type: entry.type, fromDay: entry.day, toDay: entry.day)
        return entry.type == .menstrualFlow ? CycleDayRule.flowUpdate(from: samples) : CycleDayRule.spottingUpdate(from: samples)
    }

    func dailyValue(for entry: DirtyEntry, zone: TimeZone, preferredSleepSource: String?) async throws -> DailyValue? {
        switch entry.type {
        case .steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate, .bloodGlucose:
            return try await health.dailyStatistic(for: entry.type, day: entry.day, timeZone: zone).map { DailyValue(value: $0.value, minimum: $0.minimum, maximum: $0.maximum) }
        case .weight:
            let latest = try store.samples(type: .weight, fromDay: entry.day, toDay: entry.day).max { $0.end < $1.end }
            guard let latest, case .quantity(let kilograms) = latest.value else { return nil }
            return DailyValue(value: kilograms)
        case .sleep:
            // The day before through the day after, widened to whole nights: the night that wakes on this day may start the evening before, and a later segment may bridge into it.
            let samples = try store.sleepSamples(from: entry.day.adding(days: -1).interval(in: zone).start, to: entry.day.adding(days: 1).interval(in: zone).end)
            let nights = SleepAggregator.nights(from: samples, preferredSource: preferredSleepSource, fallback: zone)
            guard let night = nights[entry.day] else { return nil }
            return DailyValue(value: night.asleepHours, deepHours: night.deepHours, remHours: night.remHours, source: night.source)
        case .menstrualFlow, .spotting:
            // Never reached: cycle days go through cycleDayUpdate.
            return nil
        }
    }

    static let readmePath = "Vital Courier/README.md"

    static func jsonPath(type: HealthType, monthKey: String) -> String {
        "Vital Courier/json/\(type.folderName)/\(monthKey).json"
    }

    static func notePath(day: DayKey) -> String {
        "Vital Courier/daily/\(day).md"
    }

    func writeStep(types: [HealthType], zone: TimeZone, errors: inout [String]) -> (written: Int, failed: Int, pending: Int) {
        let enabled = Set(types)
        let entries: [DirtyEntry]
        do {
            entries = try store.dirtyEntries().filter { enabled.contains($0.type) }
        } catch {
            errors.append("write: \(error)")
            return (0, 0, 0)
        }
        let entriesByDay = Dictionary(grouping: entries, by: \.day)
        if entriesByDay.isEmpty { return (0, 0, 0) }
        guard let destination = destination() else {
            errors.append("no folder picked")
            return (0, 0, entriesByDay.count)
        }
        // README first, so a failure can't leave it missing with no dirty state to retry it: on failure the days are still written but no mark clears.
        var readmeWritten = true
        do {
            try destination.write(Data(MarkdownWriter.readme.utf8), to: Self.readmePath)
        } catch {
            readmeWritten = false
            errors.append("readme: \(error)")
        }
        let generatedAt = now()
        var monthFileWritten: [String: Bool] = [:]
        var written = 0
        var failed = 0
        var pending = 0
        let days = entriesByDay.keys.sorted()
        for (index, day) in days.enumerated() {
            if Task.isCancelled {
                pending += days.count - index
                break
            }
            let dayEntries = entriesByDay[day]!
            var everyFileWritten = true
            for entry in dayEntries {
                let path = Self.jsonPath(type: entry.type, monthKey: day.monthKey)
                if monthFileWritten[path] == nil {
                    do {
                        let samples = try store.samples(type: entry.type, month: day.monthKey)
                        let data = try JSONWriter.monthFile(type: entry.type, monthKey: day.monthKey, samples: samples, timeZone: zone, generatedAt: generatedAt)
                        try destination.write(data, to: path)
                        monthFileWritten[path] = true
                    } catch {
                        monthFileWritten[path] = false
                        errors.append("json \(entry.type.folderName) \(day.monthKey): \(error)")
                    }
                }
                if monthFileWritten[path] != true { everyFileWritten = false }
            }
            guard dayEntries.allSatisfy(\.fresh) else {
                if everyFileWritten { pending += 1 } else { failed += 1 }
                continue
            }
            do {
                // Stored cycle keys are kept whatever the switch says, so a note doesn't change with when it was last rewritten.
                let summary = DailySummary(day: day, values: try store.dailyValues(day: day), cycle: try store.cycleDay(day: day))
                try destination.write(MarkdownWriter.note(for: summary), to: Self.notePath(day: day))
            } catch {
                everyFileWritten = false
                errors.append("note \(day): \(error)")
            }
            guard everyFileWritten, readmeWritten else {
                failed += 1
                continue
            }
            do {
                // A mark that went stale again mid-run stays dirty: the day is pending, not written.
                if try store.clearDirty(day: day, types: dayEntries.map(\.type)) {
                    written += 1
                } else {
                    pending += 1
                }
            } catch {
                failed += 1
                errors.append("clear \(day): \(error)")
            }
        }
        return (written, failed, pending)
    }
}
