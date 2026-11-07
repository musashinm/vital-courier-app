import Foundation

/// What the run detail's "Data read" section shows (Run Detail Types Plan, Decision 6).
public enum RunDataRead: Equatable, Sendable {
  case hidden
  case noNewData
  case types([HealthType])

  public init(run: RunRecord) {
    guard let changedTypes = run.changedTypes else {
      self = .hidden
      return
    }
    if changedTypes.isEmpty {
      self = run.readOutcome == ReadOutcome.read.rawValue ? .noNewData : .hidden
    } else {
      self = .types(HealthType.allCases.filter(Set(changedTypes).contains))
    }
  }
}
