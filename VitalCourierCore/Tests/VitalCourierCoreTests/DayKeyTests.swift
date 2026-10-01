import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct DayKeyTests {
    @Test func usesTheSampleMetadataZoneWhenPresent() {
        // 01:30 UTC is 02:30 on the 27th in Lisbon and 22:30 on the 26th in Sao Paulo.
        let sample = makeSample(start: "2026-09-27T01:30:00Z", zone: "Europe/Lisbon")
        #expect(DayAssigner.day(for: sample, fallback: saoPaulo) == day("2026-09-27"))
    }

    @Test func fallsBackToThePhoneZoneWithoutMetadata() {
        let sample = makeSample(start: "2026-09-27T01:30:00Z")
        #expect(DayAssigner.day(for: sample, fallback: saoPaulo) == day("2026-09-26"))
    }

    @Test func aTripSampleKeepsItsOwnZoneAfterComingHome() {
        // 23:30 UTC is 00:30 on the 28th in Lisbon; the phone is back in Sao Paulo (20:30 on the 27th).
        let sample = makeSample(start: "2026-09-27T23:30:00Z", zone: "Europe/Lisbon")
        #expect(DayAssigner.day(for: sample, fallback: saoPaulo) == day("2026-09-28"))
    }

    @Test func wakeDayUsesTheEndDate() {
        let sample = makeSample(type: .sleep, start: "2026-09-27T01:00:00Z", end: "2026-09-27T10:00:00Z", value: .category("asleepCore"))
        #expect(DayAssigner.wakeDay(for: sample, fallback: saoPaulo) == day("2026-09-27"))
    }

    @Test func formatsAndParsesDayAndMonthKeys() {
        let key = DayKey(year: 2026, month: 9, day: 7)
        #expect(key.description == "2026-09-07")
        #expect(key.monthKey == "2026-09")
        #expect(DayKey("2026-09-07") == key)
        #expect(DayKey("not a day") == nil)
    }

    @Test func rejectsMalformedAndImpossibleDays() {
        #expect(DayKey("2026--09-07") == nil)
        #expect(DayKey("2026-02-30") == nil)
        #expect(DayKey("2026-9-07") == nil)
        #expect(DayKey("2026-09-07x") == nil)
        #expect(DayKey("2024-02-29") == day("2024-02-29"))
    }

    @Test func addsDaysAcrossAMonthBoundary() {
        #expect(day("2026-10-01").adding(days: -1) == day("2026-09-30"))
        #expect(day("2026-09-30").adding(days: 1) == day("2026-10-01"))
    }

    @Test func dayIntervalIsLocalMidnightToMidnight() {
        let interval = day("2026-09-27").interval(in: saoPaulo)
        #expect(interval.start == date("2026-09-27T03:00:00Z"))
        #expect(interval.duration == 24 * 60 * 60)
    }

    @Test func sortsChronologically() {
        #expect(day("2026-09-30") < day("2026-10-01"))
        #expect(day("2025-12-31") < day("2026-01-01"))
    }
}
