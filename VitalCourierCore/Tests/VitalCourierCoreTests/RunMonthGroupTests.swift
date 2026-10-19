import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct RunMonthGroupTests {
  func run(_ start: String, id: Int64) -> RunRecord {
    RunRecord(
      startedAt: date(start), trigger: "appOpen", readOutcome: "read", daysWritten: 0, daysFailed: 0, daysPending: 0,
      errors: [], id: id)
  }

  @Test func runsGroupByMonthInOrder() {
    let runs = [
      run("2026-10-02T12:00:00Z", id: 3), run("2026-10-01T12:00:00Z", id: 2), run("2026-09-30T12:00:00Z", id: 1),
    ]

    let groups = RunMonthGroup.groups(runs, timeZone: saoPaulo)

    #expect(groups.map(\.month) == [MonthKey(year: 2026, month: 10), MonthKey(year: 2026, month: 9)])
    #expect(groups.map(\.id) == groups.map(\.month))
    #expect(groups.map { $0.runs.map(\.id) } == [[3, 2], [1]])
  }

  @Test func aRunJustAfterMidnightUTCBelongsToTheLocalMonth() {
    // 01:00 UTC on Oct 1 is 22:00 on Sep 30 in São Paulo.
    let groups = RunMonthGroup.groups([run("2026-10-01T01:00:00Z", id: 1)], timeZone: saoPaulo)
    #expect(groups.map(\.month) == [MonthKey(year: 2026, month: 9)])
    #expect(
      RunMonthGroup.groups([run("2026-10-01T01:00:00Z", id: 1)], timeZone: utc).map(\.month) == [
        MonthKey(year: 2026, month: 10)
      ])
  }
}
