import Foundation
import GRDB
import Testing

@testable import VitalCourierCore

@Suite struct LocalStoreRunTypesTests {
  func run(changedTypes: [HealthType]?, startedAt: Double = 1_790_000_000) -> RunRecord {
    RunRecord(
      startedAt: Date(timeIntervalSince1970: startedAt), trigger: "appOpen", readOutcome: "read", daysWritten: 0,
      daysFailed: 0, daysPending: 0, errors: [], changedTypes: changedTypes)
  }

  @Test func existingRunsSurviveTheRunTypesMigration() throws {
    let dbQueue = try DatabaseQueue()
    try LocalStore.migrator.migrate(dbQueue, upTo: "v3-dailyValueMinMax")
    try dbQueue.write { db in
      try db.execute(
        sql:
          "INSERT INTO runRecord (startedAt, triggerName, readOutcome, daysWritten, daysFailed, daysPending, errors) VALUES (1790000000, 'appOpen', 'read', 3, 1, 2, '[\"read: x\"]')"
      )
      try db.execute(
        sql:
          "INSERT INTO runRecord (startedAt, triggerName, readOutcome, daysWritten, daysFailed, daysPending, errors) VALUES (1790000100, 'appEvent', 'notRequested', 0, 0, 0, '[\"file protection: x\"]')"
      )
    }

    let store = try LocalStore(dbQueue: dbQueue)

    let runs = try store.recentRuns(limit: 10)
    #expect(runs.count == 2)
    let appEvent = try #require(runs.first { $0.trigger == "appEvent" })
    #expect(appEvent.startedAt == Date(timeIntervalSince1970: 1_790_000_100))
    #expect(appEvent.readOutcome == "notRequested")
    #expect(appEvent.daysWritten == 0)
    #expect(appEvent.daysFailed == 0)
    #expect(appEvent.daysPending == 0)
    #expect(appEvent.errors == ["file protection: x"])
    #expect(appEvent.changedTypes == nil)
    let appOpen = try #require(runs.first { $0.trigger == "appOpen" })
    #expect(appOpen.startedAt == Date(timeIntervalSince1970: 1_790_000_000))
    #expect(appOpen.readOutcome == "read")
    #expect(appOpen.daysWritten == 3)
    #expect(appOpen.daysFailed == 1)
    #expect(appOpen.daysPending == 2)
    #expect(appOpen.errors == ["read: x"])
    #expect(appOpen.changedTypes == nil)
  }

  @Test func changedTypesRoundTrip() throws {
    let store = try LocalStore.inMemory()
    try store.appendRun(run(changedTypes: nil, startedAt: 1_790_000_001))
    try store.appendRun(run(changedTypes: [], startedAt: 1_790_000_002))
    try store.appendRun(run(changedTypes: [.weight, .steps], startedAt: 1_790_000_003))

    let changedTypesNewestFirst = try store.recentRuns(limit: 3).map(\.changedTypes)
    #expect(changedTypesNewestFirst.count == 3)
    #expect(changedTypesNewestFirst[0] == [.steps, .weight])
    #expect(changedTypesNewestFirst[1] == [])
    #expect(changedTypesNewestFirst[2] == nil)
  }

  @Test func appEventsHaveNoChangedTypes() throws {
    let store = try LocalStore.inMemory()
    try store.recordAppEvent(errors: ["boom"], at: Date(timeIntervalSince1970: 1_790_000_000))

    #expect(try store.recentRuns(limit: 1).first?.changedTypes == nil)
  }

  @Test func anUnknownChangedTypeRaisesCorruptRow() throws {
    let dbQueue = try DatabaseQueue()
    let store = try LocalStore(dbQueue: dbQueue)
    try dbQueue.write { db in
      try db.execute(
        sql:
          "INSERT INTO runRecord (startedAt, triggerName, readOutcome, daysWritten, daysFailed, daysPending, errors, changedTypes) VALUES (1790000000, 'appOpen', 'read', 0, 0, 0, '[]', '[\"nonsense\"]')"
      )
    }

    do {
      _ = try store.recentRuns(limit: 1)
      Issue.record("expected recentRuns to throw")
    } catch LocalStoreError.corruptRow(let detail) {
      #expect(detail == "runRecord changedTypes [\"nonsense\"]")
    } catch {
      Issue.record("expected LocalStoreError.corruptRow, got \(error)")
    }
  }
}
