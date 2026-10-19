import Foundation
import VitalCourierCore

/// Dates in the app's copy: "today at 8:16 AM", "yesterday", "Sep 24" in English; "hoje às 08:16", "ontem", "24 de set." in Portuguese. Words come from the catalog, month names from the locale, and the locale picks a 12- or 24-hour clock.
struct StatusDateFormatter {
  let localization: AppLocalization
  let timeZone: TimeZone

  init(localization: AppLocalization = .system, timeZone: TimeZone = .current) {
    self.localization = localization
    self.timeZone = timeZone
  }

  func time(_ date: Date) -> String {
    // ICU puts a narrow no-break space before AM/PM; the design copy uses a plain space.
    let pattern = (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: localization.locale) ?? "HH:mm")
      .replacingOccurrences(of: "\u{202F}", with: " ")
    let formatter = DateFormatter()
    // The pattern already carries the locale's clock; POSIX keeps "AM"/"PM" spelled the way the design writes them.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }

  func day(_ day: DayKey, today: DayKey) -> String {
    if day == today { return localization.string("today") }
    if day == today.adding(days: -1) { return localization.string("yesterday") }
    let start = day.interval(in: timeZone).start
    let style =
      day.year == today.year ? dateStyle.month(.abbreviated).day() : dateStyle.month(.abbreviated).day().year()
    return start.formatted(style)
  }

  func moment(_ date: Date, now: Date) -> String {
    let dayText = day(DayKey(date: date, timeZone: timeZone), today: DayKey(date: now, timeZone: timeZone))
    return localization.string("\(dayText) at \(time(date))")
  }

  /// Run detail: "Oct 3, 2026 at 8:16 AM".
  func fullMoment(_ date: Date) -> String {
    let dateText = date.formatted(dateStyle.month(.abbreviated).day().year())
    return localization.string("\(dateText) at \(time(date))")
  }

  /// History section header: "October 2026", "Outubro de 2026".
  func monthTitle(_ month: MonthKey) -> String {
    let firstDay = DayKey(year: month.year, month: month.month, day: 1).interval(in: timeZone).start
    return capitalizedFirst(firstDay.formatted(dateStyle.month(.wide).year()))
  }

  func capitalizedFirst(_ text: String) -> String {
    text.prefix(1).uppercased(with: localization.locale) + text.dropFirst()
  }

  private var dateStyle: Date.FormatStyle {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    return Date.FormatStyle(locale: localization.locale, calendar: gregorian, timeZone: timeZone)
  }
}
