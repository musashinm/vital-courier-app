import Foundation
import HealthKit
import Testing
import VitalCourierCore

@testable import VitalCourierHealthKit

/// Ties section 6 of `SCHEMA.md` (repo root) to `HealthKitMapping.categoryValueCatalog`. Runs under `swift test`.
@Suite struct SchemaCategoryDocTests {
  /// Four components up from this file: `VitalCourierHealthKitTests`, `Tests`, `VitalCourierCore`, then the repo root.
  static func schemaDocument() throws -> String {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return try String(contentsOf: url.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
  }

  /// The text between the "Category values" heading and the next heading.
  static func sectionSix(_ document: String) throws -> [String] {
    let lines = document.components(separatedBy: "\n")
    let start = try #require(lines.firstIndex { $0.hasPrefix("#") && $0.contains("Category values") })
    let rest = lines[(start + 1)...]
    let end = rest.firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
    return Array(lines[(start + 1)..<end])
  }

  static let categoryTypes: [HealthType] = [.sleep, .menstrualFlow, .spotting]

  static func catalog(_ type: HealthType) -> [(rawValue: Int, name: String)] {
    HealthKitMapping.categoryValueCatalog[type] ?? []
  }

  @Test func catalogMatchesSection6() throws {
    #expect(Set(HealthKitMapping.categoryValueCatalog.keys) == Set(Self.categoryTypes))
    let section = try Self.sectionSix(try Self.schemaDocument())
    let text = section.joined(separator: "\n")
    let catalogNames = Set(Self.categoryTypes.flatMap { Self.catalog($0).map(\.name) })

    for name in catalogNames {
      #expect(text.contains("`\(name)`"), "section 6 does not document the category value \(name)")
    }
    // The value lists are the lines that start with a type label. Other backticked words in section 6 are prose.
    let valueLines = section.filter {
      $0.hasPrefix("Sleep:") || $0.hasPrefix("Menstrual flow:") || $0.hasPrefix("Spotting:")
    }
    #expect(valueLines.count == Self.categoryTypes.count)
    let documented = Set(valueLines.flatMap { $0.matches(of: /`([^`]+)`/).map { String($0.output.1) } })
    for token in documented where token != "unknown(<n>)" {
      #expect(catalogNames.contains(token), "section 6 lists \(token), which the catalog does not have")
    }
  }

  @Test func mappingRoundTripsTheCatalog() {
    for type in Self.categoryTypes {
      for entry in Self.catalog(type) {
        #expect(
          HealthKitMapping.categoryValueName(rawValue: entry.rawValue, for: type) == entry.name,
          "\(type) raw value \(entry.rawValue)")
      }
    }
  }

  @Test func mappingProducesNothingElse() {
    for type in Self.categoryTypes {
      let known = Set(Self.catalog(type).map(\.rawValue))
      for rawValue in -1...64 where !known.contains(rawValue) {
        #expect(
          HealthKitMapping.categoryValueName(rawValue: rawValue, for: type) == "unknown(\(rawValue))",
          "\(type) raw value \(rawValue)")
      }
    }
  }

  @Test func catalogCoversTheHealthKitEnums() {
    let sleepCases: [HKCategoryValueSleepAnalysis] = [
      .inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM,
    ]
    let bleedingCases: [HKCategoryValueVaginalBleeding] = [.unspecified, .light, .medium, .heavy, .none]
    let sleepRaw = Set(Self.catalog(.sleep).map(\.rawValue))
    let flowRaw = Set(Self.catalog(.menstrualFlow).map(\.rawValue))
    for value in sleepCases { #expect(sleepRaw.contains(value.rawValue), "sleep \(value) missing from the catalog") }
    for value in bleedingCases { #expect(flowRaw.contains(value.rawValue), "flow \(value) missing from the catalog") }
    for type in Self.categoryTypes {
      let raw = Self.catalog(type).map(\.rawValue)
      #expect(Set(raw).count == raw.count, "\(type) catalog repeats a raw value")
    }
  }
}
