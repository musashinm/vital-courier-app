import Foundation

/// How many days a run wrote, failed to write, and left pending.
struct DayCounts {
  var written = 0
  var failed = 0
  var pending = 0
}

extension ExportRunner {
  // swiftlint:disable function_parameter_count - the run passes its once-read settings down
  /// Runs after Verify. A run that can query Health goes month by month, newest first: daily values for the month, then its files, so a cut-short run leaves whole months written (spec, Write as it goes). A run that can't query Health writes everything in one pass.
  func exportStep(
    types: [HealthType], readable: [HealthType], zone: TimeZone, queriesHealth: Bool, writesStaleJSON: Bool,
    errors: inout [String]
  ) async -> DayCounts {
    let entries: [DirtyEntry]
    do {
      entries = try dirtyEntries(of: types, month: nil)
    } catch {
      errors.append("write: \(error)")
      return DayCounts()
    }
    if entries.isEmpty { return DayCounts() }
    let destination = destination()
    var readmeWritten = true
    if let destination {
      // README first, so a failure can't leave it missing with no dirty state to retry it: on failure the days are still written but no mark clears.
      do {
        try destination.write(Data(MarkdownWriter.readme.utf8), to: Self.readmePath)
      } catch {
        readmeWritten = false
        errors.append("readme: \(error)")
      }
    } else {
      errors.append("no folder picked")
    }
    let daysByMonth = Dictionary(grouping: entries, by: { $0.day.monthKey }).mapValues { Set($0.map(\.day)).count }
    let months: [String?] = queriesHealth ? daysByMonth.keys.sorted(by: >) : [nil]
    let allDaysCount = Set(entries.map(\.day)).count
    func dayCount(of month: String?) -> Int { month.flatMap { daysByMonth[$0] } ?? allDaysCount }
    var counts = DayCounts()
    var healthRefusedStatistics = false
    for (index, month) in months.enumerated() {
      if Task.isCancelled {
        counts.pending += months[index...].reduce(0) { $0 + dayCount(of: $1) }
        break
      }
      if queriesHealth && !healthRefusedStatistics {
        let finished = await dailyValuesStep(
          types: types, readable: readable, zone: zone, month: month, errors: &errors)
        healthRefusedStatistics = !finished
      }
      guard let destination else {
        counts.pending += dayCount(of: month)
        continue
      }
      let monthCounts = writeStep(
        types: types, zone: zone, month: month, writesStaleJSON: writesStaleJSON, readmeWritten: readmeWritten,
        destination: destination, errors: &errors)
      counts.written += monthCounts.written
      counts.failed += monthCounts.failed
      counts.pending += monthCounts.pending
    }
    return counts
  }

  // swiftlint:enable function_parameter_count

  /// The dirty entries of the enabled types, optionally of one month (`YYYY-MM`) only.
  func dirtyEntries(of types: [HealthType], month: String?) throws -> [DirtyEntry] {
    let enabled = Set(types)
    return try store.dirtyEntries().filter { entry in
      enabled.contains(entry.type) && (month == nil || entry.day.monthKey == month)
    }
  }

  // swiftlint:disable cyclomatic_complexity function_body_length function_parameter_count - long by design; splitting it is a separate refactor
  /// Writes the files of the days in `month` (all days when nil) and clears the marks of the days it finished. A stale entry's month JSON is written only when `writesStaleJSON` is set (Rebuild all).
  func writeStep(
    types: [HealthType], zone: TimeZone, month: String?, writesStaleJSON: Bool, readmeWritten: Bool,
    destination: any ExportDestination, errors: inout [String]
  ) -> DayCounts {
    let entries: [DirtyEntry]
    do {
      entries = try dirtyEntries(of: types, month: month)
    } catch {
      errors.append("write: \(error)")
      return DayCounts()
    }
    let entriesByDay = Dictionary(grouping: entries, by: \.day)
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
      guard let dayEntries = entriesByDay[day] else {
        preconditionFailure("days holds only keys of entriesByDay")
      }
      var everyFileWritten = true
      for entry in dayEntries {
        let path = Self.jsonPath(type: entry.type, monthKey: day.monthKey)
        // Only Rebuild all rewrites the JSON of a stale entry.
        if monthFileWritten[path] == nil && (entry.fresh || writesStaleJSON) {
          do {
            let samples = try store.samples(type: entry.type, month: day.monthKey)
            let data = try JSONWriter.monthFile(
              type: entry.type, monthKey: day.monthKey, samples: samples, timeZone: zone, generatedAt: generatedAt)
            try destination.write(data, to: path)
            monthFileWritten[path] = true
          } catch {
            monthFileWritten[path] = false
            errors.append("json \(entry.type.folderName) \(day.monthKey): \(error)")
          }
        }
        if (entry.fresh || writesStaleJSON) && monthFileWritten[path] == false { everyFileWritten = false }
      }
      guard dayEntries.allSatisfy(\.fresh) else {
        if everyFileWritten { pending += 1 } else { failed += 1 }
        continue
      }
      do {
        // Stored cycle keys are kept whatever the switch says, so a note doesn't change with when it was last rewritten.
        let summary = DailySummary(
          day: day, values: try store.dailyValues(day: day), cycle: try store.cycleDay(day: day))
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
    return DayCounts(written: written, failed: failed, pending: pending)
  }
  // swiftlint:enable cyclomatic_complexity function_body_length function_parameter_count
}
