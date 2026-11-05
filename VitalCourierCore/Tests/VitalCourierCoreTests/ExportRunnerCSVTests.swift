import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct ExportRunnerCSVTests {
  typealias FormatSettings = ExportRunnerFormatTests.FormatSettings

  let stepsCSV = "Vital Courier/csv/steps/2026-09.csv"
  let stepsJSON = "Vital Courier/json/steps/2026-09.json"
  let allFormats: Set<ExportFormat> = [.json, .markdown, .csv]

  func makeRunner(
    store: LocalStore, health: FakeHealthSource, destination: FakeDestination, formats: FormatSettings
  ) -> ExportRunner {
    let fixedNow = date("2026-09-30T15:00:00Z")
    return ExportRunner(
      store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { saoPaulo },
      exportFormats: { formats.selected }, coveredExportFormats: { formats.covered },
      setCoveredExportFormats: { formats.covered = $0 })
  }

  func run(_ runner: ExportRunner) async -> RunOutcome {
    await runner.run(trigger: .observerWake, options: .forTrigger(.observerWake)) {}
  }

  func healthWithOneStepsSample() async -> FakeHealthSource {
    let health = FakeHealthSource()
    await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)
    await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
    return health
  }

  @Test func csvIsWrittenOnlyWhenSelected() async throws {
    let defaultFormats = FormatSettings()
    let defaultDestination = FakeDestination()
    _ = await run(
      makeRunner(
        store: try LocalStore.inMemory(), health: await healthWithOneStepsSample(), destination: defaultDestination,
        formats: defaultFormats))

    let withCSV = FormatSettings()
    withCSV.selected = allFormats
    withCSV.covered = allFormats
    let csvDestination = FakeDestination()
    _ = await run(
      makeRunner(
        store: try LocalStore.inMemory(), health: await healthWithOneStepsSample(), destination: csvDestination,
        formats: withCSV))

    #expect(!defaultDestination.paths.contains(stepsCSV))
    #expect(csvDestination.paths.contains(stepsCSV))
    #expect(csvDestination.text(at: stepsCSV)?.hasPrefix("uuid,start,end,value,unit,source,device,metadata\n") == true)
    #expect(csvDestination.text(at: "Vital Courier/README.md")?.contains("csv/<type>/<YYYY-MM>.csv") == true)
  }

  @Test func aFailedCSVWriteHoldsTheMarks() async throws {
    let store = try LocalStore.inMemory()
    let destination = FakeDestination()
    destination.failWrites(to: stepsCSV)
    let formats = FormatSettings()
    formats.selected = allFormats
    formats.covered = allFormats

    let outcome = await run(
      makeRunner(store: store, health: await healthWithOneStepsSample(), destination: destination, formats: formats))

    #expect(outcome.daysWritten == 0)
    #expect(outcome.daysFailed == 1)
    #expect(try store.dirtyEntries().count == 1)
    #expect(destination.paths.contains(stepsJSON))
  }

  @Test func turningCSVOnBackfillsEveryMonth() async throws {
    let store = try LocalStore.inMemory()
    for start in ["2026-08-15T12:00:00Z", "2026-09-27T12:00:00Z"] {
      try store.applyChanges(
        HealthChanges(added: [makeSample(start: start)]), for: .steps, fallbackTimeZone: saoPaulo)
    }
    for dayText in ["2026-08-15", "2026-09-27"] {
      try store.saveDailyValue(DailyValue(value: 100), type: .steps, day: day(dayText))
      try store.clearDirty(type: .steps, day: day(dayText))
    }
    let health = FakeHealthSource()
    await health.setRefuseReads(true)
    let destination = FakeDestination()
    let formats = FormatSettings()
    formats.selected = allFormats

    let outcome = await run(makeRunner(store: store, health: health, destination: destination, formats: formats))

    #expect(outcome.daysWritten == 2)
    #expect(destination.paths.contains("Vital Courier/csv/steps/2026-08.csv"))
    #expect(destination.paths.contains(stepsCSV))
    #expect(formats.covered == allFormats)
    #expect(try store.dirtyEntries().isEmpty)
  }

  @Test func jsonAndCSVShareOneMonthLoad() async throws {
    let store = try LocalStore.inMemory()
    let destination = FakeDestination()
    let formats = FormatSettings()
    formats.selected = allFormats
    formats.covered = allFormats
    // A sample stored after the JSON is written shows up in the CSV only if the CSV loaded the month again.
    destination.runOnFirstWrite(to: stepsJSON) {
      try? store.applyChanges(
        HealthChanges(added: [makeSample(start: "2026-09-27T13:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    }

    _ = await run(
      makeRunner(store: store, health: await healthWithOneStepsSample(), destination: destination, formats: formats))

    let csvRows = destination.text(at: stepsCSV)?.split(separator: "\n").count
    #expect(csvRows == 2)
    #expect(try store.samples(type: .steps, month: "2026-09").count == 2)
  }
}
