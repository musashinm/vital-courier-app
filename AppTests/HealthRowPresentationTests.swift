import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct HealthRowPresentationTests {
  let today = day("2026-11-16")
  let setupDay = day("2026-10-01")
  let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)

  func snapshot(
    daily: [HealthType: String] = [:], sleepSource: String? = nil, flowDay: String? = nil, flow: String? = nil,
    spottingDay: String? = nil
  ) -> StoreStatusSnapshot {
    StoreStatusSnapshot(
      latestRun: nil, lastSuccessfulReadAt: nil, dailyValuesFailureStreakStart: nil,
      latestDailyValueDays: daily.mapValues(day), latestSleepSource: sleepSource, latestFlowDay: flowDay.map(day),
      latestFlow: flow, latestSpottingDay: spottingDay.map(day)
    )
  }

  func resolve(
    _ type: HealthType, _ snapshot: StoreStatusSnapshot?, setupDay: DayKey? = day("2026-10-01"), today: DayKey? = nil
  ) -> HealthRowPresentation {
    HealthRowPresentation.resolve(
      type: type, snapshot: snapshot, setupDay: setupDay, today: today ?? self.today, formatter: english)
  }

  @Test func dailyTypeUpdatedTodayReadsItsDay() {
    let row = resolve(.steps, snapshot(daily: [.steps: "2026-11-16"]))
    #expect(row.valueText == "Updated today")
    #expect(row.isSilent == false)
    #expect(row.latestDay == day("2026-11-16"))
  }

  @Test func dailyTypeSilentForAWeek() {
    let row = resolve(.steps, snapshot(daily: [.steps: "2026-11-09"]))
    #expect(row.valueText == "No data received in 7 days")
    #expect(row.isSilent == true)
  }

  @Test func sleepCarriesItsSource() {
    let withSource = snapshot(daily: [.sleep: "2026-11-16", .steps: "2026-11-16"], sleepSource: "Apple Watch")
    #expect(resolve(.sleep, withSource).valueText == "Updated today · Apple Watch")
    #expect(resolve(.steps, withSource).valueText == "Updated today")
  }

  @Test func flowUsesTheCycleTextAndIsNeverSilent() {
    let flowSnapshot = snapshot(flowDay: "2026-09-01", flow: "heavy")
    let row = resolve(.menstrualFlow, flowSnapshot)
    #expect(
      row.valueText
        == CycleRowText.valueText(for: .menstrualFlow, snapshot: flowSnapshot, formatter: english, today: today))
    #expect(row.isSilent == false)
    #expect(row.latestDay == day("2026-09-01"))
  }

  @Test func spottingUsesItsOwnDay() {
    let row = resolve(.spotting, snapshot(spottingDay: "2026-11-15"))
    #expect(row.latestDay == day("2026-11-15"))
    #expect(row.isSilent == false)
  }

  @Test func nilSnapshotResolvesEveryPathWithoutData() {
    for type in HealthType.allCases {
      let row = resolve(type, nil, setupDay: nil)
      #expect(row.latestDay == nil)
      #expect(row.isSilent == false)
      #expect(row.valueText == (HealthType.cycleTypes.contains(type) ? "No entries yet" : "No data yet"))
    }
  }

  @Test func neverSeenTypeGoesSilentSevenDaysAfterSetup() {
    let silent = resolve(.steps, snapshot(), today: day("2026-10-08"))
    #expect(silent.isSilent == true)
    #expect(silent.valueText == "No data received in 7 days")
    #expect(silent.latestDay == nil)
    let waiting = resolve(.steps, snapshot(), today: day("2026-10-07"))
    #expect(waiting.isSilent == false)
    #expect(waiting.valueText == "No data yet")
  }

  @Test func noSetupDayNeverGoesSilent() {
    #expect(resolve(.steps, snapshot(), setupDay: nil, today: day("2027-11-16")).isSilent == false)
  }
}
