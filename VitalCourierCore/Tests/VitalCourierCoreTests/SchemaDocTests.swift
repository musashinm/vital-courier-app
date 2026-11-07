import Foundation
import Testing

@testable import VitalCourierCore

/// Ties `SCHEMA.md` (repo root) to what the writers emit. Runs under `swift test`, not the Xcode test phase.
@Suite struct SchemaDocTests {
  /// Four components up from this file: `VitalCourierCoreTests`, `Tests`, `VitalCourierCore`, then the repo root.
  static func schemaDocument() throws -> String {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return try String(contentsOf: url.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
  }

  static func backticked(_ token: String) -> String { "`\(token)`" }

  /// A summary with every value, minimum, maximum and cycle flag set.
  static func fullyPopulatedSummary() -> DailySummary {
    var values: [HealthType: DailyValue] = [:]
    for type in HealthType.allCases {
      values[type] = DailyValue(
        value: 1.5, deepHours: 1.0, remHours: 0.5, source: "Apple Watch", minimum: 1.0, maximum: 2.0)
    }
    let summary = DailySummary(
      day: DayKey(year: 2026, month: 11, day: 7), values: values,
      cycle: CycleDay(flow: "heavy", periodStart: true, spotting: true))
    return summary
  }

  static func keys(inNote data: Data) -> [String] {
    // swiftlint:disable:next optional_data_string_conversion - test helper; the bytes are valid UTF-8
    String(decoding: data, as: UTF8.self)
      .split(separator: "\n")
      .filter { $0 != "---" }
      .compactMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) }
  }

  @Test func noteEmitsExactlyTheKeyContract() {
    let emitted = Self.keys(inNote: MarkdownWriter.note(for: Self.fullyPopulatedSummary()))
    #expect(Set(MarkdownWriter.frontmatterKeys).count == MarkdownWriter.frontmatterKeys.count, "duplicate contract key")
    #expect(
      emitted == MarkdownWriter.frontmatterKeys,
      "note(for:) and MarkdownWriter.frontmatterKeys disagree. Emitted: \(emitted)")

    let minimal = Self.keys(inNote: MarkdownWriter.note(for: DailySummary(day: DayKey(year: 2026, month: 11, day: 7))))
    let contractOrder = MarkdownWriter.frontmatterKeys.filter(minimal.contains)
    #expect(minimal == contractOrder, "a summary with no values must emit a subset of the contract, in order")
    #expect(minimal == ["date", "vc_schema"], "only date and vc_schema are unconditional. Emitted: \(minimal)")
  }

  @Test func everyNoteKeyIsDocumented() throws {
    let summary = Self.fullyPopulatedSummary()
    for child in Mirror(reflecting: summary).children {
      let label = child.label ?? "?"
      let inner = Mirror(reflecting: child.value)
      if inner.displayStyle == .optional {
        #expect(inner.children.count == 1, "fixture leaves \(label) nil")
        if let unwrapped = inner.children.first?.value as? Bool { #expect(unwrapped, "fixture leaves \(label) false") }
      } else if let flag = child.value as? Bool {
        #expect(flag, "fixture leaves \(label) false")
      }
    }

    let document = try Self.schemaDocument()
    for key in MarkdownWriter.frontmatterKeys {
      #expect(document.contains(Self.backticked(key)), "SCHEMA.md does not document the key \(key)")
    }
    let documentedKeys = Set(
      document.matches(of: /`(vc_[a-z0-9_]+)`/).map { String($0.output.1) })
    for key in documentedKeys {
      #expect(
        MarkdownWriter.frontmatterKeys.contains(key), "SCHEMA.md documents \(key), which the writer does not emit")
    }
  }

  @Test func csvHeaderIsDocumentedVerbatim() throws {
    let document = try Self.schemaDocument()
    #expect(document.contains(Self.backticked(CSVWriter.header)))
  }

  @Test func everyTypeIsDocumented() throws {
    let document = try Self.schemaDocument()
    for type in HealthType.allCases {
      for token in [type.rawValue, type.folderName, type.siUnit] {
        #expect(document.contains(Self.backticked(token)), "SCHEMA.md does not document \(token) for \(type)")
      }
    }
  }

  @Test func jsonKeysAreDocumented() throws {
    let sample = makeSample(type: .steps, start: "2026-09-27T12:00:00Z", value: .quantity(10))
    let data = try JSONWriter.monthFile(
      type: .steps, monthKey: "2026-09", samples: [sample], timeZone: saoPaulo,
      generatedAt: date("2026-09-30T15:00:00Z"))
    let file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let period = try #require(file["period"] as? [String: Any])
    let entry = try #require((file["samples"] as? [[String: Any]])?.first)

    let document = try Self.schemaDocument()
    for key in Set(file.keys).union(period.keys).union(entry.keys) {
      #expect(document.contains(Self.backticked(key)), "SCHEMA.md does not document the JSON key \(key)")
    }
  }

  @Test func documentVersionMatchesTheCode() throws {
    let document = try Self.schemaDocument()
    let versions = document.matches(of: /(?m)^Version: (\d+)$/).compactMap { Int($0.output.1) }
    #expect(versions == [ExportSchema.version], "SCHEMA.md Version line \(versions) vs ExportSchema.version")
  }
}
