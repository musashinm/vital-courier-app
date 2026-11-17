import Foundation
import VitalCourierCore

/// One Apple Health category on Home: its enabled types' rows, folded into a count, a latest day and a silent count.
struct CategoryPresentation: Equatable {
  let category: HealthCategory
  let rows: [HealthRowPresentation]

  var typeCount: Int { rows.count }
  var silentCount: Int { rows.filter(\.isSilent).count }
  var latestDay: DayKey? { rows.compactMap(\.latestDay).max() }

  /// The second line of the category row. A silent type outranks everything, then the newest day, then "no data".
  func summaryText(formatter: StatusDateFormatter, today: DayKey) -> String {
    let localization = formatter.localization
    let typeCount = typeCount
    let silentCount = silentCount
    let isCycle = category == .cycleTracking
    if silentCount > 0 {
      return localization.string("\(typeCount) types · \(silentCount) silent for a week")
    }
    if let latestDay {
      let dayText = formatter.day(latestDay, today: today)
      return isCycle
        ? localization.string("\(typeCount) types · Latest entry \(dayText)")
        : localization.string("\(typeCount) types · Latest \(dayText)")
    }
    return isCycle
      ? localization.string("\(typeCount) types · No entries yet")
      : localization.string("\(typeCount) types · No data yet")
  }

  /// The VoiceOver label of the combined category row, built per state rather than from the visible text.
  func accessibilityLabel(formatter: StatusDateFormatter, today: DayKey) -> String {
    let localization = formatter.localization
    let name = category.name(in: localization)
    let typeCount = typeCount
    let silentCount = silentCount
    let isCycle = category == .cycleTracking
    if silentCount > 0 {
      return localization.string("\(name). \(typeCount) types. \(silentCount) types have been silent for a week.")
    }
    if let latestDay {
      let dayText = formatter.day(latestDay, today: today)
      return isCycle
        ? localization.string("\(name). \(typeCount) types. Latest entry \(dayText).")
        : localization.string("\(name). \(typeCount) types. Latest \(dayText).")
    }
    return isCycle
      ? localization.string("\(name). \(typeCount) types. No entries yet.")
      : localization.string("\(name). \(typeCount) types. No data yet.")
  }
}

/// One entry of Home's "Health data" section.
enum HomeHealthItem: Equatable, Identifiable {
  case type(HealthRowPresentation)
  case category(CategoryPresentation)

  var id: String {
    switch self {
    case .type(let row): "type-\(row.type.rawValue)"
    case .category(let presentation): "category-\(presentation.category)"
    }
  }
}

enum HomeHealthItems {
  /// Walks `HealthCategory.allCases`, so a one-type category sits at its category's position. A category with no
  /// enabled type is skipped, one type is shown as that type's row, two or more become a category row.
  static func items(
    enabledTypes: [HealthType], resolve: (HealthType) -> HealthRowPresentation
  ) -> [HomeHealthItem] {
    HealthCategory.allCases.compactMap { category in
      let rows = rows(of: category, enabledTypes: enabledTypes, resolve: resolve)
      switch rows.count {
      case 0: return nil
      case 1: return .type(rows[0])
      default: return .category(CategoryPresentation(category: category, rows: rows))
      }
    }
  }

  /// The live rows of one category, in `enabledTypes` order, for the detail screen (zero, one or many).
  static func rows(
    of category: HealthCategory, enabledTypes: [HealthType], resolve: (HealthType) -> HealthRowPresentation
  ) -> [HealthRowPresentation] {
    enabledTypes.filter { $0.category == category }.map(resolve)
  }
}

/// The category detail's two groups: silent types first, then the rest, each sorted by name.
struct CategoryDetailSections: Equatable {
  let needsAttention: [HealthRowPresentation]
  let others: [HealthRowPresentation]

  var isEmpty: Bool { needsAttention.isEmpty && others.isEmpty }

  init(rows: [HealthRowPresentation], name: (HealthType) -> String = { $0.displayName }) {
    let sorted = rows.sorted { name($0.type).localizedStandardCompare(name($1.type)) == .orderedAscending }
    needsAttention = sorted.filter(\.isSilent)
    others = sorted.filter { !$0.isSilent }
  }
}
