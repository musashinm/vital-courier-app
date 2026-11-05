import Foundation

public enum CSVWriterError: Error, Equatable {
  case metadataIsNotUTF8
}

public enum CSVWriter {
  static let header = "uuid,start,end,value,unit,source,device,metadata"

  /// One month of one type: a header and a row per sample, sorted like the JSON. RFC 4180 quoting, LF line endings, UTF-8 without a byte order mark.
  public static func monthFile(type: HealthType, samples: [HealthSample], timeZone: TimeZone) throws -> Data {
    let ordered = samples.sorted { ($0.start, $0.uuid.uuidString) < ($1.start, $1.uuid.uuidString) }
    var formatters = JSONWriter.FormatterCache()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var file = Data()
    file.reserveCapacity((header.utf8.count + 1) + ordered.count * estimatedRowBytes)
    file.append(contentsOf: header.utf8)
    file.append(newline)
    for sample in ordered {
      try autoreleasepool {
        let sampleZone = DayAssigner.zone(for: sample, fallback: timeZone)
        guard let metadata = String(bytes: try encoder.encode(sample.metadata), encoding: .utf8) else {
          throw CSVWriterError.metadataIsNotUTF8
        }
        let cells = [
          sample.uuid.uuidString,
          formatters.string(from: sample.start, in: sampleZone, fractionalSeconds: true),
          formatters.string(from: sample.end, in: sampleZone, fractionalSeconds: true),
          valueText(sample.value),
          type.siUnit,
          withoutFormulaRisk(sample.source),
          sample.device.map(withoutFormulaRisk) ?? "",
          metadata,
        ]
        file.append(contentsOf: cells.map(escaped).joined(separator: ",").utf8)
        file.append(newline)
      }
    }
    return file
  }

  /// A UUID, two timestamps, a number, a unit and a short source and metadata come to about this many bytes.
  private static let estimatedRowBytes = 160
  private static let newline = UInt8(ascii: "\n")

  private static func valueText(_ value: SampleValue) -> String {
    switch value {
    case .quantity(let number): number.description
    case .category(let name): name
    }
  }

  /// Spreadsheets run a cell that starts with one of these as a formula, and other apps choose source and device names.
  private static func withoutFormulaRisk(_ text: String) -> String {
    guard let first = text.unicodeScalars.first, formulaStarts.contains(first) else { return text }
    return "'" + text
  }

  private static let formulaStarts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

  /// Works on scalars because Swift reads CR LF as one `Character` that equals neither CR nor LF.
  private static func escaped(_ cell: String) -> String {
    let needsQuotes = cell.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
    guard needsQuotes else { return cell }
    var result = "\""
    for scalar in cell.unicodeScalars {
      if scalar == "\"" { result += "\"" }
      result.unicodeScalars.append(scalar)
    }
    return result + "\""
  }
}
