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
    var lines = [header]
    for sample in ordered {
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
      lines.append(cells.map(escaped).joined(separator: ","))
    }
    return Data((lines.joined(separator: "\n") + "\n").utf8)
  }

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
