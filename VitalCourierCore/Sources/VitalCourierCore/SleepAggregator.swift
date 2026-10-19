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

  /// One source's longest cluster for a wake day, and whether any of its samples came from a Watch.
  struct Candidate {
    let night: SleepNight
    let isWatch: Bool
  }

  public static func nights(from samples: [HealthSample], preferredSource: String?, fallback: TimeZone) -> [DayKey:
    SleepNight]
  {
    let asleepSamples = samples.filter { sample in
      if case .category(let stage) = sample.value { asleepValues.contains(stage) } else { false }
    }
    var candidatesByDay: [DayKey: [Candidate]] = [:]
    for (source, sourceSamples) in Dictionary(grouping: asleepSamples, by: \.source) {
      var longestByDay: [DayKey: Candidate] = [:]
      for cluster in clusters(of: sourceSamples) {
        let candidate = summarize(cluster, source: source, fallback: fallback)
        let wakeDay = candidate.night.wakeDay
        if let existing = longestByDay[wakeDay], existing.night.asleepHours >= candidate.night.asleepHours { continue }
        longestByDay[wakeDay] = candidate
      }
      for (wakeDay, candidate) in longestByDay {
        candidatesByDay[wakeDay, default: []].append(candidate)
      }
    }
    return candidatesByDay.mapValues { pick(from: $0, preferredSource: preferredSource) }
  }

  static func isAsleep(_ sample: HealthSample) -> Bool {
    if case .category(let stage) = sample.value { asleepValues.contains(stage) } else { false }
  }

  /// Wake days of every night (per source, no source preference) that contains one of `seeds`, plus the UUIDs of all samples in those nights. Used to find which notes a changed sample can affect.
  static func affectedNights(in samples: [HealthSample], containing seeds: Set<UUID>, fallback: TimeZone) -> (
    wakeDays: Set<DayKey>, members: Set<UUID>
  ) {
    var wakeDays: Set<DayKey> = []
    var members: Set<UUID> = []
    for sourceSamples in Dictionary(grouping: samples.filter(isAsleep), by: \.source).values {
      for cluster in clusters(of: sourceSamples) where cluster.contains(where: { seeds.contains($0.uuid) }) {
        guard let lastSample = cluster.max(by: { $0.end < $1.end }) else {
          preconditionFailure("a cluster always holds at least one sample")
        }
        wakeDays.insert(DayAssigner.wakeDay(for: lastSample, fallback: fallback))
        members.formUnion(cluster.map(\.uuid))
      }
    }
    return (wakeDays, members)
  }

  /// Wake days whose notes can change when the stored sample `uuid` is replaced by `incoming` (an add or a re-delivery) or removed (`incoming` nil). `stored` must hold every stored sleep sample near the change, including whole nights. Covers the nights the sample was in, the nights it ends up in, and every pre-existing night a new sample bridges.
  static func wakeDaysAffected(
    stored: [HealthSample], replacing uuid: UUID, with incoming: HealthSample?, fallback: TimeZone
  ) -> Set<DayKey> {
    let before = affectedNights(in: stored, containing: [uuid], fallback: fallback)
    let remaining = stored.filter { $0.uuid != uuid } + (incoming.map { [$0] } ?? [])
    let after = affectedNights(
      in: remaining, containing: before.members.union(incoming == nil ? [] : [uuid]), fallback: fallback)
    // The incoming sample was not stored yet, so the nights it bridges only show up by looking back at the stored set.
    let bridged = affectedNights(in: stored, containing: after.members, fallback: fallback)
    return before.wakeDays.union(after.wakeDays).union(bridged.wakeDays)
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

  static func summarize(_ cluster: [HealthSample], source: String, fallback: TimeZone) -> Candidate {
    /// Hours covered by the union of the matching samples' intervals, so overlaps never count twice.
    func hours(where include: (String) -> Bool) -> Double {
      let intervals =
        cluster
        .filter { sample in
          if case .category(let stage) = sample.value { include(stage) } else { false }
        }
        .map { ($0.start, $0.end) }
        .sorted { $0.0 < $1.0 }
      var total: TimeInterval = 0
      var current: (start: Date, end: Date)?
      for interval in intervals {
        if let open = current, interval.0 <= open.end {
          current = (open.start, max(open.end, interval.1))
        } else {
          if let open = current { total += open.end.timeIntervalSince(open.start) }
          current = interval
        }
      }
      if let open = current { total += open.end.timeIntervalSince(open.start) }
      return total / secondsPerHour
    }
    guard let lastSample = cluster.max(by: { $0.end < $1.end }) else {
      preconditionFailure("a cluster always holds at least one sample")
    }
    let night = SleepNight(
      wakeDay: DayAssigner.wakeDay(for: lastSample, fallback: fallback),
      source: source,
      asleepHours: hours { asleepValues.contains($0) },
      deepHours: hours { $0 == "asleepDeep" },
      remHours: hours { $0 == "asleepREM" }
    )
    return Candidate(night: night, isWatch: cluster.contains { $0.device?.contains("Watch") == true })
  }

  static func pick(from candidates: [Candidate], preferredSource: String?) -> SleepNight {
    if let preferredSource, let preferred = candidates.first(where: { $0.night.source == preferredSource }) {
      return preferred.night
    }
    let watchCandidates = candidates.filter(\.isWatch)
    let pool = (watchCandidates.isEmpty ? candidates : watchCandidates).map(\.night)
    // Most asleep time wins; on a tie the alphabetically first source wins.
    guard let best = pool.max(by: { ($0.asleepHours, $1.source) < ($1.asleepHours, $0.source) }) else {
      preconditionFailure("pick(from:) is only called with at least one candidate")
    }
    return best
  }
}
