import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct LocalStoreStateTests {
  func storeWithOneDirtyStepsDay() throws -> LocalStore {
    let store = try LocalStore.inMemory()
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    return store
  }

  @Test func savingADailyValueMarksItsEntryFresh() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.saveDailyValue(DailyValue(value: 8412), type: .steps, day: day("2026-09-27"))

    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true)])
    #expect(try store.dailyValues(day: day("2026-09-27")) == [.steps: DailyValue(value: 8412)])
  }

  @Test func savingNilDeletesTheValueAndStillMarksFresh() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.saveDailyValue(DailyValue(value: 10), type: .steps, day: day("2026-09-27"))
    try store.saveDailyValue(nil, type: .steps, day: day("2026-09-27"))

    #expect(try store.dailyValues(day: day("2026-09-27")).isEmpty)
    #expect(try store.dirtyEntries().first?.fresh == true)
  }

  @Test func newChangesMakeAFreshEntryStaleAgain() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.saveDailyValue(DailyValue(value: 10), type: .steps, day: day("2026-09-27"))
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T13:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)

    #expect(try store.dirtyEntries().first?.fresh == false)
  }

  @Test func clearDirtyRemovesOnlyThatEntry() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.applyChanges(
      HealthChanges(added: [makeSample(type: .weight, start: "2026-09-27T12:00:00Z", value: .quantity(72))]),
      for: .weight, fallbackTimeZone: saoPaulo)
    try store.clearDirty(type: .steps, day: day("2026-09-27"))

    #expect(try store.dirtyEntries().map(\.type) == [.weight])
  }

  @Test func clearDirtyForADayClearsAllGivenTypesTogether() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.applyChanges(
      HealthChanges(added: [makeSample(type: .weight, start: "2026-09-27T12:00:00Z", value: .quantity(72))]),
      for: .weight, fallbackTimeZone: saoPaulo)
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-28T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27"))
    try store.saveDailyValue(DailyValue(value: 72), type: .weight, day: day("2026-09-27"))
    try store.clearDirty(day: day("2026-09-27"), types: [.steps, .weight])

    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-28"), fresh: false)])
  }

  @Test func markAllDirtyCoversEveryStoredDayAsStale() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-29T12:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27"))
    try store.clearDirty(type: .steps, day: day("2026-09-29"))
    try store.markAllDirty(statisticsZone: saoPaulo)

    #expect(
      try store.dirtyEntries() == [
        DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false),
        DirtyEntry(type: .steps, day: day("2026-09-29"), fresh: false),
      ])
  }

  @Test func storesTheSleepSourcePreference() throws {
    let store = try LocalStore.inMemory()
    #expect(try store.sleepSourcePreference() == nil)
    try store.setSleepSourcePreference("Oura")
    #expect(try store.sleepSourcePreference() == "Oura")
    try store.setSleepSourcePreference(nil)
    #expect(try store.sleepSourcePreference() == nil)
  }

  @Test func keepsRunHistoryNewestFirst() throws {
    let store = try LocalStore.inMemory()
    var older = RunRecord(
      startedAt: date("2026-09-27T10:00:00Z"), trigger: "appOpen", readOutcome: "read", daysWritten: 1, daysFailed: 0,
      daysPending: 0, errors: [])
    var newer = RunRecord(
      startedAt: date("2026-09-27T11:00:00Z"), trigger: "appIntent", readOutcome: "not requested", daysWritten: 0,
      daysFailed: 1, daysPending: 2, errors: ["json steps 2026-09: disk full"])
    try store.appendRun(older)
    try store.appendRun(newer)
    older.id = 1
    newer.id = 2

    #expect(try store.recentRuns(limit: 10) == [newer, older])
    #expect(try store.recentRuns(limit: 1) == [newer])
  }

  @Test func clearLocalCopyKeepsSettingsAndHistory() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.applyChanges(HealthChanges(newAnchor: Data([9])), for: .steps, fallbackTimeZone: saoPaulo)
    try store.saveDailyValue(DailyValue(value: 5), type: .steps, day: day("2026-09-27"))
    try store.setSleepSourcePreference("Oura")
    try store.appendRun(
      RunRecord(
        startedAt: date("2026-09-27T10:00:00Z"), trigger: "appOpen", readOutcome: "read", daysWritten: 1, daysFailed: 0,
        daysPending: 0, errors: []))
    try store.clearLocalCopy()

    #expect(try store.samples(type: .steps, month: "2026-09").isEmpty)
    #expect(try store.anchor(for: .steps) == nil)
    #expect(try store.dirtyEntries().isEmpty)
    #expect(try store.dailyValues(day: day("2026-09-27")).isEmpty)
    #expect(try store.sleepSourcePreference() == "Oura")
    #expect(try store.recentRuns(limit: 10).count == 1)
  }

  @Test func savingADailyValueOnACleanStoreCreatesAFreshMark() throws {
    let store = try LocalStore.inMemory()
    try store.saveDailyValue(DailyValue(value: 3), type: .steps, day: day("2026-09-27"))
    try store.saveDailyValue(nil, type: .weight, day: day("2026-09-27"))

    #expect(
      try store.dirtyEntries() == [
        DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: true),
        DirtyEntry(type: .weight, day: day("2026-09-27"), fresh: true),
      ])
  }

  @Test func ordersRunHistoryByStartTimeNotInsertionOrder() throws {
    let store = try LocalStore.inMemory()
    var newerStart = RunRecord(
      startedAt: date("2026-09-27T11:00:00Z"), trigger: "appIntent", readOutcome: "read", daysWritten: 0, daysFailed: 0,
      daysPending: 0, errors: [])
    var olderStart = RunRecord(
      startedAt: date("2026-09-27T10:00:00Z"), trigger: "appOpen", readOutcome: "read", daysWritten: 0, daysFailed: 0,
      daysPending: 0, errors: [])
    try store.appendRun(newerStart)
    try store.appendRun(olderStart)
    newerStart.id = 1
    olderStart.id = 2

    #expect(try store.recentRuns(limit: 10) == [newerStart, olderStart])
  }

  @Test func clearingADayLeavesAMarkThatWentStaleAgain() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27"))
    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T13:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)

    try store.clearDirty(day: day("2026-09-27"), types: [.steps])

    #expect(try store.dirtyEntries() == [DirtyEntry(type: .steps, day: day("2026-09-27"), fresh: false)])
  }

  @Test func clearingADayReportsWhetherEveryMarkWasCleared() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27"))
    let allCleared = try store.clearDirty(day: day("2026-09-27"), types: [.steps])
    #expect(allCleared == true)

    try store.applyChanges(
      HealthChanges(added: [makeSample(start: "2026-09-27T13:00:00Z")]), for: .steps, fallbackTimeZone: saoPaulo)
    let staleCleared = try store.clearDirty(day: day("2026-09-27"), types: [.steps])
    #expect(staleCleared == false)
  }

  @Test func clearingADayIsAllOrNothingWhenOneTypeWentStale() throws {
    let store = try storeWithOneDirtyStepsDay()
    try store.applyChanges(
      HealthChanges(added: [makeSample(type: .weight, start: "2026-09-27T12:00:00Z", value: .quantity(72))]),
      for: .weight, fallbackTimeZone: saoPaulo)
    try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27"))
    // Weight stays stale (fresh = 0), steps is fresh.

    let allCleared = try store.clearDirty(day: day("2026-09-27"), types: [.steps, .weight])

    #expect(allCleared == false)
    #expect(Set(try store.dirtyEntries().map(\.type)) == [.steps, .weight])
  }
}
