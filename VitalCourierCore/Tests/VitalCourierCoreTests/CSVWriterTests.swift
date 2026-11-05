import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct CSVWriterTests {
  let header = "uuid,start,end,value,unit,source,device,metadata"

  func csv(_ samples: [HealthSample], type: HealthType = .steps, zone: TimeZone = saoPaulo) throws -> String {
    // swiftlint:disable:next optional_data_string_conversion - test helper; the bytes are valid UTF-8
    String(decoding: try CSVWriter.monthFile(type: type, samples: samples, timeZone: zone), as: UTF8.self)
  }

  func row(_ output: [String], _ index: Int) -> String { output.indices.contains(index) ? output[index] : "" }

  func lines(_ samples: [HealthSample], type: HealthType = .steps, zone: TimeZone = saoPaulo) throws -> [String] {
    try csv(samples, type: type, zone: zone).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  @Test func headerIsExact() throws {
    let output = try lines([])
    #expect(row(output, 0) == header)
    #expect(try csv([]) == header + "\n")
  }

  @Test func quantityRow() throws {
    let sample = makeSample(
      start: "2026-09-27T12:00:00Z", end: "2026-09-27T12:30:00Z", value: .quantity(8412), source: "iPhone",
      device: nil)
    let output = try lines([sample])

    #expect(
      row(output, 1)
        == "\(sample.uuid.uuidString),2026-09-27T09:00:00.000-03:00,2026-09-27T09:30:00.000-03:00,8412.0,count,iPhone,,{}"
    )
    #expect(output.count == 3 && row(output, 2).isEmpty)
  }

  @Test func categoryRowsCarryTheName() throws {
    let sleep = makeSample(type: .sleep, start: "2026-09-27T01:00:00Z", value: .category("asleepREM"))
    let flow = makeSample(type: .menstrualFlow, start: "2026-09-27T01:00:00Z", value: .category("medium"))

    #expect(row(try lines([sleep], type: .sleep), 1).contains(",asleepREM,category,"))
    #expect(row(try lines([flow], type: .menstrualFlow), 1).contains(",medium,category,"))
  }

  @Test func commasQuotesAndNewlinesAreQuoted() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", source: "a,\"b\"\nc", device: "plain")
    let output = try csv([sample])

    #expect(output.contains(",\"a,\"\"b\"\"\nc\",plain,"))
  }

  @Test func metadataIsASortedJSONStringAndQuoted() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", metadata: ["b": "2", "a": "1/x"])

    #expect(try csv([sample]).contains(",iPhone,iPhone,\"{\"\"a\"\":\"\"1/x\"\",\"\"b\"\":\"\"2\"\"}\"\n"))
  }

  @Test(arguments: ["=SUM(A1)", "+1", "-1", "@cmd", "\tx", "\rx"])
  func formulaLikeSourceAndDeviceGetAQuotePrefix(name: String) throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", source: name, device: name)
    let output = try csv([sample])
    let prefixed = name.unicodeScalars.contains("\r") ? "\"'\(name)\"" : "'\(name)"

    #expect(output.contains(",\(prefixed),\(prefixed),"))
  }

  @Test func aCarriageReturnLineFeedInASourceIsQuotedAndPrefixed() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", source: "\r\nx", device: "a\r\nb")
    let output = try csv([sample])

    #expect(output.contains(",\"'\r\nx\",\"a\r\nb\","))
  }

  @Test func numbersKeepTheirMinusSign() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", value: .quantity(-3.5))

    #expect(try csv([sample]).contains(",-3.5,count,"))
  }

  @Test func timestampsMatchTheJSON() throws {
    let sample = makeSample(
      type: .sleep, start: "2026-09-27T01:00:00Z", end: "2026-09-27T02:00:00.5Z", zone: "Europe/Lisbon")
    let json = try #require(
      try JSONSerialization.jsonObject(
        with: try JSONWriter.monthFile(
          type: .sleep, monthKey: "2026-09", samples: [sample], timeZone: saoPaulo,
          generatedAt: date("2026-09-30T15:00:00Z")))
        as? [String: Any])
    let entry = try #require((json["samples"] as? [[String: Any]])?.first)
    let start = try #require(entry["start"] as? String)
    let end = try #require(entry["end"] as? String)

    #expect(row(try lines([sample], type: .sleep), 1).contains(",\(start),\(end),"))
  }

  @Test func rowsSortLikeTheJSON() throws {
    let later = makeSample(start: "2026-09-27T13:00:00Z")
    let sameStartHigh = makeSample(
      start: "2026-09-27T12:00:00Z", uuid: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!)
    let sameStartLow = makeSample(
      start: "2026-09-27T12:00:00Z", uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let output = try lines([later, sameStartHigh, sameStartLow])

    #expect(row(output, 1).hasPrefix("00000000-0000-0000-0000-000000000001,"))
    #expect(row(output, 2).hasPrefix("FFFFFFFF-"))
    #expect(row(output, 3).hasPrefix(later.uuid.uuidString))
  }

  @Test func numbersUseAPointInPtBR() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", value: .quantity(12345.5))
    let output = try csv([sample])

    #expect(output.contains(",12345.5,count,"))
  }

  @Test func theFileHasNoByteOrderMark() throws {
    let data = try CSVWriter.monthFile(type: .steps, samples: [], timeZone: saoPaulo)

    #expect(data.prefix(3) != Data([0xEF, 0xBB, 0xBF]))
    #expect(data.prefix(4) == Data("uuid".utf8))
  }

  @Test func theCSVPathMirrorsTheJSONPath() {
    #expect(
      ExportRunner.csvPath(type: .menstrualFlow, monthKey: "2026-09") == "Vital Courier/csv/menstrual-flow/2026-09.csv")
  }
}
