import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct ExportRunnerFreshnessTests {
  let now = date("2026-09-30T15:00:00Z")
  let note27 = "Vital Courier/daily/2026-09-27.md"

  func makeRunner(store: LocalStore, health: FakeHealthSource, destination: FakeDestination?) -> ExportRunner {
    let fixedNow = now
    return ExportRunner(
      store: store, health: health, destination: { destination }, now: { fixedNow }, timeZone: { saoPaulo })
  }

  @Test func aFailingDailyQueryInvalidatesAnEntryThatWasFreshFromAnEarlierRun() async throws {
    let store = try LocalStore.inMemory()
    let health = FakeHealthSource()
    await health.queue(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps)
    await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
    // First run has no folder: the value is stored fresh, the note is not written, the mark stays.
    _ = await makeRunner(store: store, health: health, destination: nil).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}
    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true)])

    await health.failStatistic(for: .steps, day: day("2026-09-27"))
    let destination = FakeDestination()
    let outcome = await makeRunner(store: store, health: health, destination: destination).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}

    #expect(destination.text(at: note27) == nil)
    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
    #expect(outcome.daysWritten == 0)
  }

  @Test func aFailedReadOfOneTypeStillRefreshesDailyValues() async throws {
    let store = try LocalStore.inMemory()
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    let health = FakeHealthSource()
    await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))
    await health.failChanges(for: .weight)

    let outcome = await makeRunner(store: store, health: health, destination: nil).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}

    #expect(outcome.readOutcome == .failed)
    #expect(try store.dailyValues(day: day("2026-09-27")) == [.steps: DailyValue(value: 8412)])
    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true)])
  }

  @Test func aLockedRunStillSkipsDailyValues() async throws {
    let store = try LocalStore.inMemory()
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    let health = FakeHealthSource()
    await health.setReadable(false)
    await health.setStatistic(8412, for: .steps, day: day("2026-09-27"))

    _ = await makeRunner(store: store, health: health, destination: nil).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}

    #expect(try store.dailyValues(day: day("2026-09-27")).isEmpty)
  }
}
