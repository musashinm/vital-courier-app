import Foundation

/// A calendar month in some time zone: the History section key. The App names it.
public struct MonthKey: Hashable, Sendable {
  public let year: Int
  public let month: Int

  public init(year: Int, month: Int) {
    self.year = year
    self.month = month
  }
}

/// Consecutive runs of the same month (History sections).
public struct RunMonthGroup: Equatable, Sendable, Identifiable {
  public let month: MonthKey
  public let runs: [RunRecord]
  public var id: MonthKey { month }

  /// In the order given (newest first from the store). Grouping and the App's title must use the same time zone.
  public static func groups(_ runs: [RunRecord], timeZone: TimeZone) -> [RunMonthGroup] {
    var groups: [RunMonthGroup] = []
    for run in runs {
      let startDay = DayKey(date: run.startedAt, timeZone: timeZone)
      let month = MonthKey(year: startDay.year, month: startDay.month)
      if let last = groups.last, last.month == month {
        groups[groups.count - 1] = RunMonthGroup(month: month, runs: last.runs + [run])
      } else {
        groups.append(RunMonthGroup(month: month, runs: [run]))
      }
    }
    return groups
  }
}
