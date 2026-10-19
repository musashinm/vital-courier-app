import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct SleepAggregatorTests {
  func sleep(_ start: String, _ end: String, _ stage: String, source: String, device: String?) -> HealthSample {
    makeSample(type: .sleep, start: start, end: end, value: .category(stage), source: source, device: device)
  }

  // Night of the 26th to the 27th, Sao Paulo time (UTC-3).
  var phoneNight: [HealthSample] {
    [sleep("2026-09-27T02:00:00Z", "2026-09-27T09:00:00Z", "asleepUnspecified", source: "iPhone", device: "iPhone")]
  }

  var watchNight: [HealthSample] {
    [
      sleep("2026-09-27T02:30:00Z", "2026-09-27T04:30:00Z", "asleepCore", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T04:30:00Z", "2026-09-27T05:30:00Z", "asleepDeep", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T05:30:00Z", "2026-09-27T05:45:00Z", "awake", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T05:45:00Z", "2026-09-27T07:15:00Z", "asleepREM", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T01:30:00Z", "2026-09-27T08:00:00Z", "inBed", source: "Watch", device: "Apple Watch"),
    ]
  }

  @Test func prefersTheWatchOverAnotherSourceWithMoreSleep() throws {
    let nights = SleepAggregator.nights(from: phoneNight + watchNight, preferredSource: nil, fallback: saoPaulo)
    let night = try #require(nights[day("2026-09-27")])
    #expect(night.source == "Watch")
    #expect(night.asleepHours == 4.5)
    #expect(night.deepHours == 1)
    #expect(night.remHours == 1.5)
  }

  @Test func theUsersPickWinsWhenItHasData() throws {
    let nights = SleepAggregator.nights(from: phoneNight + watchNight, preferredSource: "iPhone", fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).source == "iPhone")
  }

  @Test func theUsersPickWithoutDataFallsBackToTheWatch() throws {
    let nights = SleepAggregator.nights(from: phoneNight + watchNight, preferredSource: "Oura", fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).source == "Watch")
  }

  @Test func withoutAWatchTheSourceWithMostSleepWins() throws {
    let other = [sleep("2026-09-27T03:00:00Z", "2026-09-27T06:00:00Z", "asleepCore", source: "Oura", device: "Ring")]
    let nights = SleepAggregator.nights(from: phoneNight + other, preferredSource: nil, fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).source == "iPhone")
  }

  @Test func anAfternoonNapDoesNotReplaceTheNight() throws {
    // 14:00 to 15:00 Sao Paulo on the 27th: more than 4 h after waking, so it is its own, shorter cluster.
    let nap = [
      sleep("2026-09-27T17:00:00Z", "2026-09-27T18:00:00Z", "asleepCore", source: "Watch", device: "Apple Watch")
    ]
    let nights = SleepAggregator.nights(from: watchNight + nap, preferredSource: nil, fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).asleepHours == 4.5)
  }

  @Test func aNightBelongsToItsWakeDate() {
    // Falls asleep at 22:00 on the 26th, wakes at 06:00 on the 27th (Sao Paulo).
    let night = [
      sleep("2026-09-27T01:00:00Z", "2026-09-27T09:00:00Z", "asleepCore", source: "Watch", device: "Apple Watch")
    ]
    let nights = SleepAggregator.nights(from: night, preferredSource: nil, fallback: saoPaulo)
    #expect(Array(nights.keys) == [day("2026-09-27")])
  }

  @Test func noAsleepSamplesMeansNoNight() {
    let onlyInBed = [
      sleep("2026-09-27T01:00:00Z", "2026-09-27T09:00:00Z", "inBed", source: "Watch", device: "Apple Watch")
    ]
    #expect(SleepAggregator.nights(from: onlyInBed, preferredSource: nil, fallback: saoPaulo).isEmpty)
  }

  @Test func duplicateOverlappingSamplesCountOnce() throws {
    let duplicated = [
      sleep("2026-09-27T01:00:00Z", "2026-09-27T09:00:00Z", "asleepCore", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T01:00:00Z", "2026-09-27T09:00:00Z", "asleepCore", source: "Watch", device: "Apple Watch"),
    ]
    let nights = SleepAggregator.nights(from: duplicated, preferredSource: nil, fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).asleepHours == 8)
  }

  @Test func partiallyOverlappingDeepSamplesCountOnce() throws {
    let overlapping = [
      sleep("2026-09-27T02:00:00Z", "2026-09-27T04:00:00Z", "asleepDeep", source: "Watch", device: "Apple Watch"),
      sleep("2026-09-27T03:00:00Z", "2026-09-27T05:00:00Z", "asleepDeep", source: "Watch", device: "Apple Watch"),
    ]
    let night = try #require(
      SleepAggregator.nights(from: overlapping, preferredSource: nil, fallback: saoPaulo)[day("2026-09-27")])
    #expect(night.deepHours == 3)
    #expect(night.asleepHours == 3)
  }

  @Test func aSourceWithWatchDataOnAnEarlierNightIsNotTheWatchTonight() throws {
    let earlierWatchNight = [
      sleep("2026-09-26T02:00:00Z", "2026-09-26T09:00:00Z", "asleepCore", source: "Wrist", device: "Apple Watch")
    ]
    let tonightWithoutWatch = [
      sleep("2026-09-27T05:00:00Z", "2026-09-27T07:00:00Z", "asleepCore", source: "Wrist", device: "Ring")
    ]
    let nights = SleepAggregator.nights(
      from: earlierWatchNight + tonightWithoutWatch + phoneNight, preferredSource: nil, fallback: saoPaulo)
    #expect(try #require(nights[day("2026-09-27")]).source == "iPhone")
    #expect(try #require(nights[day("2026-09-26")]).source == "Wrist")
  }
}
