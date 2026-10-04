import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct StatusDateFormatterTests {
    let formatter = StatusDateFormatter(timeZone: saoPaulo, locale: Locale(identifier: "en_US_POSIX"))
    // 2026-10-03 08:16 in São Paulo (UTC-3).
    let now = date("2026-10-03T11:16:00Z")

    @Test func timeFollowsTheLocaleClockWithAPlainSpace() {
        #expect(formatter.time(now) == "8:16 AM")
        #expect(StatusDateFormatter(timeZone: saoPaulo, locale: Locale(identifier: "en_GB")).time(now) == "08:16")
    }

    @Test func daysAreTodayYesterdayOrAShortDate() {
        let today = day("2026-10-03")
        #expect(formatter.day(day("2026-10-03"), today: today) == "today")
        #expect(formatter.day(day("2026-10-02"), today: today) == "yesterday")
        #expect(formatter.day(day("2026-09-24"), today: today) == "Sep 24")
        #expect(formatter.day(day("2025-12-31"), today: today) == "Dec 31, 2025")
    }

    @Test func momentsUseTheDayInTheFormattersZone() {
        #expect(formatter.moment(now, now: now) == "today at 8:16 AM")
        // 00:42 UTC on Oct 3 is 21:42 on Oct 2 in São Paulo.
        #expect(formatter.moment(date("2026-10-03T00:42:00Z"), now: now) == "yesterday at 9:42 PM")
        #expect(formatter.moment(date("2026-09-24T10:14:00Z"), now: now) == "Sep 24 at 7:14 AM")
        #expect(formatter.fullMoment(now) == "Oct 3, 2026 at 8:16 AM")
        #expect(StatusDateFormatter.capitalizedFirst("today at 8:16 AM") == "Today at 8:16 AM")
    }

    @Test func runsGroupByMonthInOrder() {
        func run(_ start: String, id: Int64) -> RunRecord {
            RunRecord(startedAt: date(start), trigger: "appOpen", readOutcome: "read", daysWritten: 0, daysFailed: 0, daysPending: 0, errors: [], id: id)
        }
        let runs = [run("2026-10-02T12:00:00Z", id: 3), run("2026-10-01T12:00:00Z", id: 2), run("2026-09-30T12:00:00Z", id: 1)]

        let groups = formatter.monthGroups(runs)

        #expect(groups.map(\.title) == ["October 2026", "September 2026"])
        #expect(groups.map { $0.runs.map(\.id) } == [[3, 2], [1]])
    }
}
