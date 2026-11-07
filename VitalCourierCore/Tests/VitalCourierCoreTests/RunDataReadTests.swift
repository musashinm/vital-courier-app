import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct RunDataReadTests {
  func run(_ readOutcome: ReadOutcome, changedTypes: [HealthType]?) -> RunRecord {
    RunRecord(
      startedAt: date("2026-10-03T11:16:00Z"), trigger: Trigger.appOpen.rawValue, readOutcome: readOutcome.rawValue,
      daysWritten: 0, daysFailed: 0, daysPending: 0, errors: [], changedTypes: changedTypes, id: 1)
  }

  @Test func oldRowsHideTheSection() {
    #expect(RunDataRead(run: run(.read, changedTypes: nil)) == .hidden)
  }

  @Test func aLockedRunWithNothingReadHidesTheSection() {
    #expect(RunDataRead(run: run(.skippedLocked, changedTypes: [])) == .hidden)
  }

  @Test func aReadWithNothingNewSaysSo() {
    #expect(RunDataRead(run: run(.read, changedTypes: [])) == .noNewData)
  }

  @Test func aFailedReadWithNothingCommittedHidesTheSection() {
    #expect(RunDataRead(run: run(.failed, changedTypes: [])) == .hidden)
  }

  @Test func aFailedRunThatCommittedSomeTypesListsThem() {
    #expect(RunDataRead(run: run(.failed, changedTypes: [.steps])) == .types([.steps]))
  }

  @Test func typesFollowSettingsOrder() {
    #expect(
      RunDataRead(run: run(.read, changedTypes: [.weight, .steps, .sleep])) == .types([.steps, .sleep, .weight]))
  }

  @Test func aLockedRunThatCommittedSomeTypesListsThem() {
    #expect(RunDataRead(run: run(.skippedLocked, changedTypes: [.steps])) == .types([.steps]))
  }
}
