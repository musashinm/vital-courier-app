import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct MarkdownWriterTests {
    func text(_ summary: DailySummary) -> String {
        String(decoding: MarkdownWriter.note(for: summary), as: UTF8.self)
    }

    @Test func writesEveryKeyInOrder() {
        var summary = DailySummary(day: day("2026-09-27"))
        summary.steps = 8412.4
        summary.exerciseMinutes = 34.9
        summary.restingHeartRateBPM = 58.46
        summary.sleepHours = 7.2
        summary.sleepDeepHours = 1.1
        summary.sleepREMHours = 1.556
        summary.sleepSource = "Kleber's Apple Watch"
        summary.weightKg = 72.44

        #expect(text(summary) == """
            ---
            date: 2026-09-27
            vc_steps: 8412
            vc_exercise_minutes: 34
            vc_resting_hr_bpm: 58.5
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

        #expect(text(summary) == """
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
        let summary = DailySummary(day: day("2026-09-27"), values: [
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

        #expect(text(summary) == """
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

        #expect(text(summary) == """
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
}
