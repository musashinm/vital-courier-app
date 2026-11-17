import Foundation
import VitalCourierCore

/// What one Health data row shows, resolved from the status snapshot. Home, the category aggregate and the category detail share it so they can't drift.
struct HealthRowPresentation: Equatable {
  let type: HealthType
  let valueText: String
  /// Drives the warning glyph and hint on the row. Never true for cycle types.
  let isSilent: Bool
  /// Daily types: the newest stored day. Flow and spotting: their own latest logged day.
  let latestDay: DayKey?

  static func resolve(
    type: HealthType, snapshot: StoreStatusSnapshot?, setupDay: DayKey?, today: DayKey,
    formatter: StatusDateFormatter
  ) -> HealthRowPresentation {
    if HealthType.cycleTypes.contains(type) {
      let latestDay: DayKey? =
        switch type {
        case .menstrualFlow: snapshot?.latestFlowDay
        case .spotting: snapshot?.latestSpottingDay
        default: nil
        }
      return HealthRowPresentation(
        type: type,
        valueText: CycleRowText.valueText(for: type, snapshot: snapshot, formatter: formatter, today: today),
        isSilent: false, latestDay: latestDay)
    }
    let latestDay = snapshot?.latestDailyValueDays[type]
    let recency = TypeRecency.resolve(latestDay: latestDay, setupDay: setupDay, today: today)
    return HealthRowPresentation(
      type: type,
      valueText: recency.valueText(
        formatter: formatter, today: today, source: type == .sleep ? snapshot?.latestSleepSource : nil),
      isSilent: recency == .silentForAWeek, latestDay: latestDay)
  }
}
