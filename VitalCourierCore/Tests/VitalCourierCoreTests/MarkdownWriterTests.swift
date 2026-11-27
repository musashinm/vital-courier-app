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
    summary.activeEnergyKcal = 511.6
    summary.walkingRunningDistanceKm = 6.4249
    summary.restingEnergyKcal = 1687.6
    summary.flightsClimbed = 7.9
    summary.standMinutes = 143.9
    summary.walkingSpeedKmh = 4.64
    summary.walkingStepLengthCm = 72.4
    summary.walkingAsymmetryPercent = 1.84
    summary.doubleSupportPercent = 28.43
    summary.restingHeartRateBPM = 58.46
    summary.walkingHeartRateAverageBPM = 92.46
    summary.heartRateBPM = 72.4
    summary.heartRateBPMMin = 48
    summary.heartRateBPMMax = 151.6
    summary.heartRateVariabilityMs = 42.4
    summary.heartRateVariabilityMsMin = 21
    summary.heartRateVariabilityMsMax = 67.6
    summary.vo2Max = 38.66
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
    summary.wristTemperatureCelsius = 35.416

    #expect(
      text(summary) == """
        ---
        date: 2026-09-27
        vc_steps: 8412
        vc_exercise_minutes: 34
        vc_active_energy_kcal: 512
        vc_distance_km: 6.42
        vc_resting_energy_kcal: 1688
        vc_flights_climbed: 7
        vc_stand_minutes: 143
        vc_walking_speed_kmh: 4.6
        vc_step_length_cm: 72
        vc_walking_asymmetry_pct: 1.8
        vc_double_support_pct: 28.4
        vc_resting_hr_bpm: 58.5
        vc_walking_hr_avg: 92.5
        vc_hr_avg: 72
        vc_hr_min: 48
        vc_hr_max: 152
        vc_hrv_ms: 42
        vc_hrv_ms_min: 21
        vc_hrv_ms_max: 68
        vc_vo2_max: 38.7
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
        vc_wrist_temp_c: 35.42
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
    #expect(MarkdownWriter.readme(formats: ExportFormat.defaultSelection).contains("overwritten"))
  }

  @Test func readmeListsOnlySelectedFormats() {
    let both = MarkdownWriter.readme(formats: [.json, .markdown])
    let jsonOnly = MarkdownWriter.readme(formats: [.json])
    let markdownOnly = MarkdownWriter.readme(formats: [.markdown])

    #expect(both.contains("json/<type>") && both.contains("daily/<YYYY-MM-DD>.md"))
    #expect(jsonOnly.contains("json/<type>") && !jsonOnly.contains("daily/"))
    #expect(markdownOnly.contains("daily/<YYYY-MM-DD>.md") && !markdownOnly.contains("json/"))
  }

  @Test(arguments: [
    Set<ExportFormat>([.json]), [.markdown], [.csv], [.json, .markdown], [.json, .markdown, .csv],
    [.json, .csv], [.markdown, .csv],
  ])
  func readmeLinksToTheSchema(formats: Set<ExportFormat>) {
    let readme = MarkdownWriter.readme(formats: formats)
    let link = "https://github.com/musashinm/vital-courier-app/blob/main/SCHEMA.md"
    #expect(readme.contains("\n\nEvery file name, property and field is described in \(link).\n"))
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

  @Test func leavesOutEnergyDistanceAndHRVWhenThereAreNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 100
    let note = text(summary)
    #expect(!note.contains("vc_active_energy_kcal"))
    #expect(!note.contains("vc_distance_km"))
    #expect(!note.contains("vc_hrv_ms"))
  }

  @Test func leavesOutRestingEnergyFlightsAndStandWhenThereAreNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 100
    let note = text(summary)
    #expect(!note.contains("vc_resting_energy_kcal"))
    #expect(!note.contains("vc_flights_climbed"))
    #expect(!note.contains("vc_stand_minutes"))
  }

  @Test func leavesOutVO2MaxWalkingSpeedAndWristTemperatureWhenThereAreNone() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.steps = 100
    let note = text(summary)
    #expect(!note.contains("vc_walking_speed_kmh"))
    #expect(!note.contains("vc_vo2_max"))
    #expect(!note.contains("vc_wrist_temp_c"))
  }

  @Test func leavesOutStepLengthAsymmetryAndDoubleSupportWhenThereAreNone() {
    let summary = DailySummary(day: day("2026-09-27"), values: [.steps: DailyValue(value: 100)])
    let note = text(summary)
    #expect(!note.contains("vc_step_length_cm"))
    #expect(!note.contains("vc_walking_asymmetry_pct"))
    #expect(!note.contains("vc_double_support_pct"))
  }

  @Test func writesAZeroWalkingAsymmetryAsZero() {
    // 0 is a value on a healthy gait; only a day without samples has no key (Walking Step Length, Asymmetry and Double Support Spec, Output).
    let summary = DailySummary(day: day("2026-09-27"), values: [.walkingAsymmetry: DailyValue(value: 0)])
    #expect(text(summary).contains("vc_walking_asymmetry_pct: 0.0\n"))
  }

  @Test func theSummaryTakesStepLengthAsymmetryAndDoubleSupportFromTheStoredDailyValues() throws {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .walkingStepLength: DailyValue(value: 72.4),
        .walkingAsymmetry: DailyValue(value: 0.0184),
        .doubleSupportTime: DailyValue(value: 0.2843),
      ])
    #expect(summary.walkingStepLengthCm == 72.4)
    #expect(abs(try #require(summary.walkingAsymmetryPercent) - 1.84) < 1e-9)
    #expect(abs(try #require(summary.doubleSupportPercent) - 28.43) < 1e-9)
    let note = text(summary)
    #expect(note.contains("vc_step_length_cm: 72\n"))
    #expect(note.contains("vc_walking_asymmetry_pct: 1.8\n"))
    #expect(note.contains("vc_double_support_pct: 28.4\n"))
  }

  @Test func roundsStepLengthAsymmetryAndDoubleSupportUpInsteadOfTruncating() {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .walkingStepLength: DailyValue(value: 72.6),
        .walkingAsymmetry: DailyValue(value: 0.0186),
        .doubleSupportTime: DailyValue(value: 0.2846),
      ])
    let note = text(summary)
    #expect(note.contains("vc_step_length_cm: 73\n"))
    #expect(note.contains("vc_walking_asymmetry_pct: 1.9\n"))
    #expect(note.contains("vc_double_support_pct: 28.5\n"))
  }

  @Test func writesAWristTemperatureWithTwoDecimals() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.wristTemperatureCelsius = 35.4
    #expect(text(summary).contains("vc_wrist_temp_c: 35.40\n"))
  }

  @Test func theSummaryTakesVO2MaxWalkingSpeedAndWristTemperatureFromTheStoredDailyValues() {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .walkingSpeed: DailyValue(value: 4.64),
        .cardioFitness: DailyValue(value: 38.66),
        .wristTemperature: DailyValue(value: 35.416),
      ])
    #expect(summary.walkingSpeedKmh == 4.64)
    #expect(summary.vo2Max == 38.66)
    #expect(summary.wristTemperatureCelsius == 35.416)
  }

  @Test func writesAZeroFlightsDayAsZero() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.flightsClimbed = 0
    #expect(text(summary).contains("vc_flights_climbed: 0\n"))
  }

  @Test func theSummaryTakesRestingEnergyFlightsAndStandFromTheStoredDailyValues() {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .restingEnergy: DailyValue(value: 1687.6),
        .flightsClimbed: DailyValue(value: 7.9),
        .standMinutes: DailyValue(value: 143.9),
      ])
    #expect(summary.restingEnergyKcal == 1687.6)
    #expect(summary.flightsClimbed == 7.9)
    #expect(summary.standMinutes == 143.9)
  }

  @Test func writesATinyDistanceAsZeroRatherThanLeavingItOut() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.walkingRunningDistanceKm = 0.004
    #expect(text(summary).contains("vc_distance_km: 0.00\n"))
  }

  @Test func writesOnlyTheHRVValuesTheDayHas() {
    var summary = DailySummary(day: day("2026-09-27"))
    summary.heartRateVariabilityMs = 40
    summary.heartRateVariabilityMsMax = 70
    let note = text(summary)
    #expect(note.contains("vc_hrv_ms: 40\nvc_hrv_ms_max: 70\n"))
    #expect(!note.contains("vc_hrv_ms_min"))
  }

  @Test func theSummaryTakesEnergyDistanceAndHRVFromTheStoredDailyValues() {
    let summary = DailySummary(
      day: day("2026-09-27"),
      values: [
        .activeEnergy: DailyValue(value: 511.6),
        .walkingRunningDistance: DailyValue(value: 6.4249),
        .heartRateVariability: DailyValue(value: 42.4, minimum: 21, maximum: 67.6),
      ])
    #expect(summary.activeEnergyKcal == 511.6)
    #expect(summary.walkingRunningDistanceKm == 6.4249)
    #expect(summary.heartRateVariabilityMs == 42.4)
    #expect(summary.heartRateVariabilityMsMin == 21)
    #expect(summary.heartRateVariabilityMsMax == 67.6)
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
