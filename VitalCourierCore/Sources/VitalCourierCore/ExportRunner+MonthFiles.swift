import Foundation

/// Whether each month file was written so far in a write step, by path.
struct MonthFileProgress {
  private var written: [String: Bool] = [:]

  func hasAttempted(_ path: String) -> Bool { written[path] != nil }

  func failed(_ path: String) -> Bool { written[path] == false }

  mutating func record(_ path: String, written didWrite: Bool) { written[path] = didWrite }
}

extension ExportRunner {

  // swiftlint:disable function_parameter_count - the write step passes its once-read context down

  /// Writes the month files of `entry` that are due and not yet attempted this step. A month's samples load once and feed both JSON and CSV, because each path is attempted once per step. A stale entry's files are written only when `writesStaleFiles` is set (Rebuild all).
  func writeMonthFiles(
    for entry: DirtyEntry, monthKey: String, formats: Set<ExportFormat>, writesStaleFiles: Bool, zone: TimeZone,
    generatedAt: Date, destination: any ExportDestination, progress: inout MonthFileProgress, errors: inout [String]
  ) {
    guard entry.fresh || writesStaleFiles else { return }
    let jsonPath = Self.jsonPath(type: entry.type, monthKey: monthKey)
    let csvPath = Self.csvPath(type: entry.type, monthKey: monthKey)
    let writesJSON = formats.contains(.json) && !progress.hasAttempted(jsonPath)
    let writesCSV = formats.contains(.csv) && !progress.hasAttempted(csvPath)
    guard writesJSON || writesCSV else { return }
    let samples: [HealthSample]
    do {
      samples = try store.samples(type: entry.type, month: monthKey)
    } catch {
      if writesJSON {
        progress.record(jsonPath, written: false)
        errors.append("json \(entry.type.folderName) \(monthKey): \(error)")
      }
      if writesCSV {
        progress.record(csvPath, written: false)
        errors.append("csv \(entry.type.folderName) \(monthKey): \(error)")
      }
      return
    }
    if writesJSON {
      do {
        let data = try JSONWriter.monthFile(
          type: entry.type, monthKey: monthKey, samples: samples, timeZone: zone, generatedAt: generatedAt)
        try destination.write(data, to: jsonPath)
        progress.record(jsonPath, written: true)
      } catch {
        progress.record(jsonPath, written: false)
        errors.append("json \(entry.type.folderName) \(monthKey): \(error)")
      }
    }
    if writesCSV {
      do {
        try destination.write(
          try CSVWriter.monthFile(type: entry.type, samples: samples, timeZone: zone), to: csvPath)
        progress.record(csvPath, written: true)
      } catch {
        progress.record(csvPath, written: false)
        errors.append("csv \(entry.type.folderName) \(monthKey): \(error)")
      }
    }
  }
  // swiftlint:enable function_parameter_count
}
