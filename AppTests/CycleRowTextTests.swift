import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct CycleRowTextTests {
  let today = day("2026-10-13")
  let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)
  let portuguese = StatusDateFormatter(localization: .portuguese, timeZone: saoPaulo)

  func snapshot(flowDay: String? = nil, flow: String? = nil, spottingDay: String? = nil) -> StoreStatusSnapshot {
    StoreStatusSnapshot(
      latestRun: nil, lastSuccessfulReadAt: nil, dailyValuesFailureStreakStart: nil, latestDailyValueDays: [:],
      latestSleepSource: nil, latestFlowDay: flowDay.map(day), latestFlow: flow, latestSpottingDay: spottingDay.map(day)
    )
  }

  @Test func flowShowsTheFlowAndTheLastLoggedDay() {
    #expect(
      CycleRowText.valueText(
        for: .menstrualFlow, snapshot: snapshot(flowDay: "2026-10-12", flow: "medium"), formatter: english, today: today
      ) == "Medium · yesterday")
    #expect(
      CycleRowText.valueText(
        for: .menstrualFlow, snapshot: snapshot(flowDay: "2026-10-02", flow: "heavy"), formatter: english, today: today)
        == "Heavy · Oct 2")
    #expect(
      CycleRowText.valueText(
        for: .menstrualFlow, snapshot: snapshot(flowDay: "2026-10-02", flow: "heavy"), formatter: portuguese,
        today: today) == "Intenso · 2 de out.")
    #expect(
      CycleRowText.valueText(
        for: .menstrualFlow, snapshot: snapshot(flowDay: "2026-10-02", flow: "none"), formatter: english, today: today)
        == "No flow · Oct 2")
  }

  @Test func spottingShowsTheLastLoggedDay() {
    #expect(
      CycleRowText.valueText(
        for: .spotting, snapshot: snapshot(spottingDay: "2026-10-13"), formatter: english, today: today) == "Today")
    #expect(
      CycleRowText.valueText(
        for: .spotting, snapshot: snapshot(spottingDay: "2026-10-02"), formatter: english, today: today) == "Oct 2")
    #expect(
      CycleRowText.valueText(
        for: .spotting, snapshot: snapshot(spottingDay: "2026-10-02"), formatter: portuguese, today: today)
        == "2 de out.")
  }

  @Test func nothingLoggedYet() {
    #expect(
      CycleRowText.valueText(for: .menstrualFlow, snapshot: snapshot(), formatter: english, today: today)
        == "No entries yet")
    #expect(
      CycleRowText.valueText(for: .spotting, snapshot: nil, formatter: portuguese, today: today)
        == "Nenhum registro ainda")
  }

  @Test func everyFlowHasAName() {
    #expect(
      ["unspecified", "light", "medium", "heavy", "none"].map { CycleRowText.flowName($0, in: .english) } == [
        "Unspecified", "Light", "Medium", "Heavy", "No flow",
      ])
    #expect(
      ["unspecified", "light", "medium", "heavy", "none"].map { CycleRowText.flowName($0, in: .portuguese) } == [
        "Não especificado", "Leve", "Médio", "Intenso", "Sem fluxo",
      ])
    #expect(CycleRowText.flowName("unknown(9)", in: .english) == "unknown(9)")
  }
}
