import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct StatusDateFormatterTests {
  let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)
  let portuguese = StatusDateFormatter(localization: .portuguese, timeZone: saoPaulo)
  // 2026-10-03 08:16 in São Paulo (UTC-3).
  let now = date("2026-10-03T11:16:00Z")

  @Test func timeFollowsTheLocaleClockWithAPlainSpace() {
    #expect(english.time(now) == "8:16 AM")
    let britishClock = StatusDateFormatter(
      localization: AppLocalization(bundle: AppLocalization.english.bundle, locale: Locale(identifier: "en_GB")),
      timeZone: saoPaulo)
    #expect(britishClock.time(now) == "08:16")
  }

  @Test func daysAreTodayYesterdayOrAShortDate() {
    let today = day("2026-10-03")
    #expect(english.day(day("2026-10-03"), today: today) == "today")
    #expect(english.day(day("2026-10-02"), today: today) == "yesterday")
    #expect(english.day(day("2026-09-24"), today: today) == "Sep 24")
    #expect(english.day(day("2025-12-31"), today: today) == "Dec 31, 2025")
  }

  @Test func momentsUseTheDayInTheFormattersZone() {
    #expect(english.moment(now, now: now) == "today at 8:16 AM")
    // 00:42 UTC on Oct 3 is 21:42 on Oct 2 in São Paulo.
    #expect(english.moment(date("2026-10-03T00:42:00Z"), now: now) == "yesterday at 9:42 PM")
    #expect(english.moment(date("2026-09-24T10:14:00Z"), now: now) == "Sep 24 at 7:14 AM")
    #expect(english.fullMoment(now) == "Oct 3, 2026 at 8:16 AM")
    #expect(english.capitalizedFirst("today at 8:16 AM") == "Today at 8:16 AM")
  }

  @Test func monthTitlesNameTheMonthAndYear() {
    #expect(english.monthTitle(MonthKey(year: 2026, month: 10)) == "October 2026")
    #expect(english.monthTitle(MonthKey(year: 2025, month: 12)) == "December 2025")
  }

  @Test func portugueseDatesUseTheBrazilianForms() {
    let today = day("2026-10-03")
    #expect(portuguese.time(now) == "08:16")
    #expect(portuguese.day(day("2026-10-03"), today: today) == "hoje")
    #expect(portuguese.day(day("2026-10-02"), today: today) == "ontem")
    #expect(portuguese.day(day("2026-09-24"), today: today) == "24 de set.")
    #expect(portuguese.day(day("2025-12-31"), today: today) == "31 de dez. de 2025")
    #expect(portuguese.moment(now, now: now) == "hoje às 08:16")
    #expect(portuguese.moment(date("2026-10-03T00:42:00Z"), now: now) == "ontem às 21:42")
    #expect(portuguese.moment(date("2026-09-24T10:14:00Z"), now: now) == "24 de set. às 07:14")
    #expect(portuguese.fullMoment(now) == "3 de out. de 2026 às 08:16")
    #expect(portuguese.capitalizedFirst("hoje às 08:16") == "Hoje às 08:16")
    #expect(portuguese.monthTitle(MonthKey(year: 2026, month: 10)) == "Outubro de 2026")
    #expect(portuguese.monthTitle(MonthKey(year: 2025, month: 12)) == "Dezembro de 2025")
  }
}
