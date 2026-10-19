import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct JSONWriterTests {
  func decode(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func writesTheFileShape() throws {
    let sample = makeSample(
      type: .weight, start: "2026-09-27T12:00:00Z", value: .quantity(72.4), source: "Scale", device: nil)
    let data = try JSONWriter.monthFile(
      type: .weight, monthKey: "2026-09", samples: [sample], timeZone: saoPaulo,
      generatedAt: date("2026-09-30T15:00:00Z"))
    let file = try decode(data)

    #expect(file["schemaVersion"] as? Int == 1)
    #expect(file["type"] as? String == "weight")
    #expect(file["unit"] as? String == "kg")
    #expect(file["generatedAt"] as? String == "2026-09-30T12:00:00-03:00")
    let period = try #require(file["period"] as? [String: Any])
    #expect(period["start"] as? String == "2026-09-01T00:00:00-03:00")
    #expect(period["end"] as? String == "2026-10-01T00:00:00-03:00")
    #expect(period["timeZone"] as? String == "America/Sao_Paulo")
    let samples = try #require(file["samples"] as? [[String: Any]])
    #expect(samples.count == 1)
    #expect(samples[0]["uuid"] as? String == sample.uuid.uuidString)
    #expect(samples[0]["value"] as? Double == 72.4)
    #expect(samples[0]["source"] as? String == "Scale")
    #expect(samples[0]["start"] as? String == "2026-09-27T09:00:00.000-03:00")
    #expect(samples[0].keys.contains("device"))
    #expect(samples[0]["device"] is NSNull)
    #expect(samples[0]["metadata"] as? [String: String] == [:])
  }

  @Test func sampleTimesCarryTheSamplesOwnOffset() throws {
    let sample = makeSample(
      type: .sleep, start: "2026-09-27T01:00:00Z", end: "2026-09-27T02:00:00Z", value: .category("asleepREM"),
      zone: "Europe/Lisbon")
    let file = try decode(
      JSONWriter.monthFile(
        type: .sleep, monthKey: "2026-09", samples: [sample], timeZone: saoPaulo,
        generatedAt: date("2026-09-30T15:00:00Z")))
    let entry = try #require((file["samples"] as? [[String: Any]])?.first)

    #expect(entry["start"] as? String == "2026-09-27T02:00:00.000+01:00")
    #expect(entry["end"] as? String == "2026-09-27T03:00:00.000+01:00")
    #expect(entry["value"] as? String == "asleepREM")
  }

  @Test func samplesAreSortedAndOutputIsDeterministic() throws {
    let later = makeSample(start: "2026-09-28T12:00:00Z")
    let earlier = makeSample(start: "2026-09-27T12:00:00Z")
    let first = try JSONWriter.monthFile(
      type: .steps, monthKey: "2026-09", samples: [later, earlier], timeZone: saoPaulo,
      generatedAt: date("2026-09-30T15:00:00Z"))
    let second = try JSONWriter.monthFile(
      type: .steps, monthKey: "2026-09", samples: [earlier, later], timeZone: saoPaulo,
      generatedAt: date("2026-09-30T15:00:00Z"))

    #expect(first == second)
    let uuids = try #require(try decode(first)["samples"] as? [[String: Any]]).compactMap { $0["uuid"] as? String }
    #expect(uuids == [earlier.uuid.uuidString, later.uuid.uuidString])
  }

  @Test func sampleTimesKeepFractionalSeconds() throws {
    let sample = makeSample(start: "2026-09-27T12:00:00Z", zone: "America/Sao_Paulo")
    var fractional = sample
    fractional.start = sample.start.addingTimeInterval(0.25)
    let file = try decode(
      JSONWriter.monthFile(
        type: .steps, monthKey: "2026-09", samples: [fractional], timeZone: saoPaulo,
        generatedAt: date("2026-09-30T15:00:00Z")))
    let entry = try #require((file["samples"] as? [[String: Any]])?.first)

    #expect(entry["start"] as? String == "2026-09-27T09:00:00.250-03:00")
  }

  @Test func theFileIsCompact() throws {
    let sample = makeSample(type: .steps, start: "2026-09-27T12:00:00Z")
    let data = try JSONWriter.monthFile(
      type: .steps, monthKey: "2026-09", samples: [sample], timeZone: saoPaulo,
      generatedAt: date("2026-09-30T15:00:00Z"))
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(!text.contains("\n"))
    #expect(!text.contains("  "))
    #expect(text.hasPrefix("{\"generatedAt\":"))
  }

  @Test func samplesInDifferentZonesKeepTheirOwnOffsetsInOneFile() throws {
    let lisbon = makeSample(
      type: .sleep, start: "2026-09-27T01:00:00Z", end: "2026-09-27T02:00:00Z", value: .category("asleepREM"),
      zone: "Europe/Lisbon")
    let saoPauloSample = makeSample(
      type: .sleep, start: "2026-09-28T01:00:00Z", end: "2026-09-28T02:00:00Z", value: .category("asleepREM"),
      zone: "America/Sao_Paulo")
    let file = try decode(
      JSONWriter.monthFile(
        type: .sleep, monthKey: "2026-09", samples: [lisbon, saoPauloSample], timeZone: saoPaulo,
        generatedAt: date("2026-09-30T15:00:00Z")))
    let entries = try #require(file["samples"] as? [[String: Any]])

    #expect(entries.count == 2)
    #expect((entries[0]["start"] as? String)?.hasPrefix("2026-09-27T02:00:00.000+01:00") == true)
    #expect((entries[1]["start"] as? String)?.hasPrefix("2026-09-27T22:00:00.000-03:00") == true)
    #expect(file["generatedAt"] as? String == "2026-09-30T12:00:00-03:00")
  }

  @Test func rejectsABadMonthKey() {
    #expect(throws: JSONWriterError.invalidMonthKey("2026-13x")) {
      try JSONWriter.monthFile(type: .steps, monthKey: "2026-13x", samples: [], timeZone: saoPaulo, generatedAt: Date())
    }
  }
}
