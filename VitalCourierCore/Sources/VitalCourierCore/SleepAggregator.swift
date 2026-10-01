import Foundation

public struct SleepNight: Equatable, Sendable {
    public let wakeDay: DayKey
    public let source: String
    public let asleepHours: Double
    public let deepHours: Double
    public let remHours: Double
}

public enum SleepAggregator {
    public static let asleepValues: Set<String> = ["asleepUnspecified", "asleepCore", "asleepDeep", "asleepREM"]
    public static let nightGap: TimeInterval = 4 * 60 * 60
    static let secondsPerHour: Double = 60 * 60

    public static func nights(from samples: [HealthSample], preferredSource: String?, fallback: TimeZone) -> [DayKey: SleepNight] {
        let asleepSamples = samples.filter { sample in
            if case .category(let stage) = sample.value { asleepValues.contains(stage) } else { false }
        }
        var candidatesByDay: [DayKey: [SleepNight]] = [:]
        var watchSources: Set<String> = []
        for (source, sourceSamples) in Dictionary(grouping: asleepSamples, by: \.source) {
            if sourceSamples.contains(where: { $0.device?.contains("Watch") == true }) {
                watchSources.insert(source)
            }
            var longestByDay: [DayKey: SleepNight] = [:]
            for cluster in clusters(of: sourceSamples) {
                let night = summarize(cluster, source: source, fallback: fallback)
                if let existing = longestByDay[night.wakeDay], existing.asleepHours >= night.asleepHours { continue }
                longestByDay[night.wakeDay] = night
            }
            for (wakeDay, night) in longestByDay {
                candidatesByDay[wakeDay, default: []].append(night)
            }
        }
        return candidatesByDay.mapValues { pick(from: $0, preferredSource: preferredSource, watchSources: watchSources) }
    }

    static func clusters(of samples: [HealthSample]) -> [[HealthSample]] {
        let ordered = samples.sorted { ($0.start, $0.uuid.uuidString) < ($1.start, $1.uuid.uuidString) }
        var result: [[HealthSample]] = []
        var clusterEnd = Date.distantPast
        for sample in ordered {
            if result.isEmpty || sample.start.timeIntervalSince(clusterEnd) >= nightGap {
                result.append([sample])
                clusterEnd = sample.end
            } else {
                result[result.count - 1].append(sample)
                clusterEnd = max(clusterEnd, sample.end)
            }
        }
        return result
    }

    static func summarize(_ cluster: [HealthSample], source: String, fallback: TimeZone) -> SleepNight {
        func hours(where include: (String) -> Bool) -> Double {
            cluster.reduce(0) { total, sample in
                guard case .category(let stage) = sample.value, include(stage) else { return total }
                return total + sample.end.timeIntervalSince(sample.start) / secondsPerHour
            }
        }
        let lastSample = cluster.max { $0.end < $1.end }!
        return SleepNight(
            wakeDay: DayAssigner.wakeDay(for: lastSample, fallback: fallback),
            source: source,
            asleepHours: hours { asleepValues.contains($0) },
            deepHours: hours { $0 == "asleepDeep" },
            remHours: hours { $0 == "asleepREM" }
        )
    }

    static func pick(from nights: [SleepNight], preferredSource: String?, watchSources: Set<String>) -> SleepNight {
        if let preferredSource, let preferred = nights.first(where: { $0.source == preferredSource }) {
            return preferred
        }
        let watchNights = nights.filter { watchSources.contains($0.source) }
        let pool = watchNights.isEmpty ? nights : watchNights
        // Most asleep time wins; on a tie the alphabetically first source wins.
        return pool.max { ($0.asleepHours, $1.source) < ($1.asleepHours, $0.source) }!
    }
}
