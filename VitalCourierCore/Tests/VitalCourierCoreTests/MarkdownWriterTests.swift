import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct MarkdownWriterTests {
  func text(_ summary: DailySummary) -> String {
    // swiftlint:disable:next optional_data_string_conversion - test helper; MarkdownWriter output is always valid UTF-8
    String(decoding: MarkdownWriter.note(for: summary), as: UTF8.self)
  }

  @Test func writesEveryKeyInOrder() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 8412.4
    summary.exerciseMinutes = 34.9
    summary.restingHeartRateBPM = 58.46
    summary.walkingHeartRateAverageBPM = 92.46
    summary.heartRateBPM = 72.4
    summary.heartRateBPMMin = 48
    summary.heartRateBPMMax = 151.6
    summary.respiratoryRate = 14.46
    summary.respiratoryRateMin = 12.1
    summary.respiratoryRateMax = 17
    summary.bloodGlucoseMgDl = 103.6
    summary.bloodGlucoseMgDlMin = 88.4
    summary.bloodGlucoseMgDlMax = 141.5
    summary.bloodOxygenPercentMin = 90.4
    summary.bloodOxygenPercentMax = 96.6
    summary.sleepHours = 7.2
    summary.sleepDeepHours = 1.1
    summary.sleepREMHours = 1.556
    summary.sleepSource = "Kleber's Apple Watch"
    summary.weightKg = 72.44

    #expect(
      text(summary) == """
        ---
        date: 2026-09-27
        vc_steps: 8412
        vc_exercise_minutes: 34
        vc_resting_hr_bpm: 58.5
        vc_walking_hr_avg: 92.5
        vc_hr_avg: 72
        vc_hr_min: 48
        vc_hr_max: 152
        vc_respiratory_rate: 14.5
        vc_respiratory_rate_min: 12.1
        vc_respiratory_rate_max: 17.0
        vc_glucose_mg_dl: 104
        vc_glucose_mg_dl_min: 88
        vc_glucose_mg_dl_max: 142
        vc_blood_oxygen_pct_min: 90
        vc_blood_oxygen_pct_max: 97
        vc_sleep_hours: 7.20
        vc_sleep_deep_hours: 1.10
        vc_sleep_rem_hours: 1.56
        vc_sleep_source: "Kleber's Apple Watch"
        vc_weight_kg: 72.4
        vc_schema: 1
        ---

        """)
  }

  @Test func leavesOutMissingKeysButKeepsARealZero() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 0

    #expect(
      text(summary) == """
        ---
        date: 2026-09-27
        vc_steps: 0
        vc_schema: 1
        ---

        """)
  }

  @Test func truncatesAFractionalStepSumLikeTheHealthApp() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 1923.6
    #expect(text(summary).contains("vc_steps: 1923\n"))

    summary.steps = 5632.5
    #expect(text(summary).contains("vc_steps: 5632\n"))

    summary.steps = -0.6
    #expect(text(summary).contains("vc_steps: 0\n"))
  }

  @Test func escapesQuotesAndBackslashesInTheSleepSource() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.sleepSource = #"My "Ring" \ v2"#
    #expect(text(summary).contains(#"vc_sleep_source: "My \"Ring\" \\ v2""#))
  }

  @Test func escapesControlCharactersInTheSleepSource() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.sleepSource = "a\nb\tc\u{0}d\r\u{80}\u{85}\u{9F}\u{FEFF}\u{FFFF}"
    #expect(text(summary).contains(#"vc_sleep_source: "a\nb\tc\x00d\r\x80\x85\x9F\uFEFF\uFFFF""#))
  }

  @Test func buildsASummaryFromStoredDailyValues() {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .steps: DailyValue(value: 100),
        .restingHeartRate: DailyValue(value: 60),
        .sleep: DailyValue(value: 7, deepHours: 1, remHours: 2, source: "Watch"),
        .weight: DailyValue(value: 70),
      ])
    #expect(summary.steps == 100)
    #expect(summary.restingHeartRateBPM == 60)
    #expect(summary.sleepHours == 7)
    #expect(summary.sleepDeepHours == 1)
    #expect(summary.sleepREMHours == 2)
    #expect(summary.sleepSource == "Watch")
    #expect(summary.weightKg == 70)
  }

  @Test func theReadmeSaysEditsGetOverwritten() {
    #expect(MarkdownWriter.readme.contains("overwritten"))
  }

  @Test func writesCycleKeysAfterWeight() {
    var summary = DailySummary(day: day("2026-10-12"))
    summary.steps = 812
    summary.weightKg = 61.2
    summary.menstrualFlow = "medium"
    summary.periodStart = true
    summary.spotting = true

    #expect(
      text(summary) == """
        ---
        date: 2026-10-12
        vc_steps: 812
        vc_weight_kg: 61.2
        vc_menstrual_flow: medium
        vc_period_start: true
        vc_spotting: true
        vc_schema: 1
        ---

        """)
  }

  @Test func falseFlagsAreLeftOut() {
    var summary = DailySummary(day: day("2026-10-12"))
    summary.menstrualFlow = "none"

    #expect(
      text(summary) == """
        ---
        date: 2026-10-12
        vc_menstrual_flow: none
        vc_schema: 1
        ---

        """)
  }

  @Test func theSummaryTakesCycleValuesFromTheCycleRow() {
    let summary = DailySummary(day: day("2026-10-12"), values: [:], cycle: CycleDay(flow: "heavy", periodStart: true))
    #expect(summary.menstrualFlow == "heavy")
    #expect(summary.periodStart)
    #expect(!summary.spotting)
    #expect(DailySummary(day: day("2026-10-12"), values: [:]).menstrualFlow == nil)
  }

  @Test func truncatesExerciseMinutesAndPlacesThemAfterSteps() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 812
    summary.exerciseMinutes = 29.99
    #expect(text(summary).contains("vc_steps: 812\nvc_exercise_minutes: 29\n"))
  }

  @Test func leavesOutExerciseMinutesWhenThereAreNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 812
    #expect(!text(summary).contains("vc_exercise_minutes"))
  }

  @Test func theSummaryTakesExerciseMinutesFromTheStoredDailyValue() {
    let summary = DailySummary(day: day("2026-09-27"), values: [.exerciseMinutes: DailyValue(value: 34)])
    #expect(summary.exerciseMinutes == 34)
  }

  @Test func leavesOutRespiratoryRateWhenThereIsNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.restingHeartRateBPM = 58
    #expect(!text(summary).contains("vc_respiratory_rate"))
  }

  @Test func writesTheRespiratoryAverageAloneWhenTheRangeIsMissing() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.respiratoryRate = 14.5
    #expect(text(summary).contains("vc_respiratory_rate: 14.5\nvc_schema: 1\n"))
    #expect(!text(summary).contains("vc_respiratory_rate_min"))
    #expect(!text(summary).contains("vc_respiratory_rate_max"))
  }

  @Test func leavesOutTheRespiratoryMaximumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.respiratoryRate = 14.5
    summary.respiratoryRateMin = 12.1
    #expect(text(summary).contains("vc_respiratory_rate: 14.5\nvc_respiratory_rate_min: 12.1\nvc_schema: 1\n"))
  }

  @Test func leavesOutTheRespiratoryMinimumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.respiratoryRate = 14.5
    summary.respiratoryRateMax = 17
    #expect(text(summary).contains("vc_respiratory_rate: 14.5\nvc_respiratory_rate_max: 17.0\nvc_schema: 1\n"))
  }

  @Test func theSummaryTakesTheRespiratoryRangeFromTheStoredDailyValue() {
    let summary = DailySummary(
      day: day("2026-09-27"), values: [.respiratoryRate: DailyValue(value: 14.5, minimum: 12.1, maximum: 17)])
    #expect(summary.respiratoryRate == 14.5)
    #expect(summary.respiratoryRateMin == 12.1)
    #expect(summary.respiratoryRateMax == 17)
  }

  @Test func leavesOutBloodGlucoseWhenThereIsNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.respiratoryRate = 14.5
    #expect(!text(summary).contains("vc_glucose"))
  }

  @Test func writesTheGlucoseAverageAloneWhenTheRangeIsMissing() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodGlucoseMgDl = 104
    #expect(text(summary).contains("vc_glucose_mg_dl: 104\nvc_schema: 1\n"))
    #expect(!text(summary).contains("vc_glucose_mg_dl_min"))
    #expect(!text(summary).contains("vc_glucose_mg_dl_max"))
  }

  @Test func leavesOutTheGlucoseMaximumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodGlucoseMgDl = 104
    summary.bloodGlucoseMgDlMin = 88
    #expect(text(summary).contains("vc_glucose_mg_dl: 104\nvc_glucose_mg_dl_min: 88\nvc_schema: 1\n"))
  }

  @Test func leavesOutTheGlucoseMinimumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodGlucoseMgDl = 104
    summary.bloodGlucoseMgDlMax = 142
    #expect(text(summary).contains("vc_glucose_mg_dl: 104\nvc_glucose_mg_dl_max: 142\nvc_schema: 1\n"))
  }

  @Test func theSummaryTakesTheGlucoseRangeFromTheStoredDailyValue() {
    let summary = DailySummary(
      day: day("2026-09-27"), values: [.bloodGlucose: DailyValue(value: 104, minimum: 88, maximum: 142)])
    #expect(summary.bloodGlucoseMgDl == 104)
    #expect(summary.bloodGlucoseMgDlMin == 88)
    #expect(summary.bloodGlucoseMgDlMax == 142)
  }

  @Test func noDecimalsRoundsToNearestWithoutGrouping() {
    #expect(MarkdownWriter.noDecimals(103.6) == "104")
    #expect(MarkdownWriter.noDecimals(88.4) == "88")
    #expect(MarkdownWriter.noDecimals(1234.4) == "1234")
  }

  @Test func theSummaryTurnsTheStoredOxygenFractionIntoPercent() {
    let summary = DailySummary(
      day: day("2026-09-27"), values: [.bloodOxygen: DailyValue(value: 0.95, minimum: 0.904, maximum: 0.966)])
    #expect(text(summary).contains("vc_blood_oxygen_pct_min: 90\nvc_blood_oxygen_pct_max: 97\nvc_schema: 1\n"))
  }

  @Test func anOvernightDipShowsAsTheMinimum() {
    let summary = DailySummary(
      day: day("2026-09-27"), values: [.bloodOxygen: DailyValue(value: 0.94, minimum: 0.75, maximum: 0.98)])
    #expect(text(summary).contains("vc_blood_oxygen_pct_min: 75\n"))
  }

  @Test func neverWritesABloodOxygenAverage() {
    let averageOnly = DailySummary(day: day("2026-09-27"), values: [.bloodOxygen: DailyValue(value: 0.95)])
    #expect(!text(averageOnly).contains("vc_blood_oxygen"))
    let fullDay = DailySummary(
      day: day("2026-09-27"), values: [.bloodOxygen: DailyValue(value: 0.95, minimum: 0.90, maximum: 0.97)])
    #expect(!text(fullDay).contains("vc_blood_oxygen_pct:"))
  }

  @Test func leavesOutBloodOxygenWhenThereIsNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodGlucoseMgDl = 104
    #expect(!text(summary).contains("vc_blood_oxygen"))
  }

  @Test func leavesOutTheOxygenMaximumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodOxygenPercentMin = 90
    #expect(text(summary).contains("vc_blood_oxygen_pct_min: 90\nvc_schema: 1\n"))
  }

  @Test func leavesOutTheOxygenMinimumOnItsOwn() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.bloodOxygenPercentMax = 97
    #expect(text(summary).contains("vc_blood_oxygen_pct_max: 97\nvc_schema: 1\n"))
  }

  @Test func leavesOutWalkingHeartRateWhenThereIsNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.restingHeartRateBPM = 58
    #expect(!text(summary).contains("vc_walking_hr_avg"))
  }

  @Test func writesAWholeWalkingHeartRateWithOneDecimal() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.walkingHeartRateAverageBPM = 90
    #expect(text(summary).contains("vc_walking_hr_avg: 90.0\nvc_schema: 1\n"))
  }

  @Test func theSummaryTakesTheWalkingHeartRateFromTheStoredDailyValue() {
    let summary = DailySummary(day: day("2026-09-27"), values: [.walkingHeartRateAverage: DailyValue(value: 92.4)])
    #expect(summary.walkingHeartRateAverageBPM == 92.4)
  }

  @Test func leavesOutHeartRateWhenThereIsNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.restingHeartRateBPM = 58
    let note = text(summary)
    #expect(!note.contains("vc_hr_avg"))
    #expect(!note.contains("vc_hr_min"))
    #expect(!note.contains("vc_hr_max"))
  }

  @Test func writesOnlyTheHeartRateValuesTheDayHas() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.heartRateBPM = 70
    summary.heartRateBPMMax = 120.5
    #expect(text(summary).contains("vc_hr_avg: 70\nvc_hr_max: 120\n"))
    #expect(!text(summary).contains("vc_hr_min"))
  }

  @Test func theSummaryTakesHeartRateFromTheStoredDailyValue() {
    let summary = DailySummary(
      day: day("2026-09-27"), values: [.heartRate: DailyValue(value: 72.4, minimum: 48, maximum: 151.6)])
    #expect(summary.heartRateBPM == 72.4)
    #expect(summary.heartRateBPMMin == 48)
    #expect(summary.heartRateBPMMax == 151.6)
  }
}
