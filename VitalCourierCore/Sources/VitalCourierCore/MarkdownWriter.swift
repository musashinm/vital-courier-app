import Foundation

public struct DailySummary: Equatable, Sendable {
    public var day: DayKey
    public var steps: Double?
    public var exerciseMinutes: Double?
    public var restingHeartRateBPM: Double?
    public var walkingHeartRateAverageBPM: Double?
    /// Breaths per minute: the day's average, lowest and highest reading.
    public var respiratoryRate: Double?
    public var respiratoryRateMin: Double?
    public var respiratoryRateMax: Double?
    /// mg/dL: the day's average, lowest and highest reading.
    public var bloodGlucoseMgDl: Double?
    public var bloodGlucoseMgDlMin: Double?
    public var bloodGlucoseMgDlMax: Double?
    public var sleepHours: Double?
    public var sleepDeepHours: Double?
    public var sleepREMHours: Double?
    public var sleepSource: String?
    public var weightKg: Double?
    public var menstrualFlow: String?
    public var periodStart = false
    public var spotting = false

    public init(day: DayKey) {
        self.day = day
    }

    public init(day: DayKey, values: [HealthType: DailyValue], cycle: CycleDay? = nil) {
        self.day = day
        steps = values[.steps]?.value
        exerciseMinutes = values[.exerciseMinutes]?.value
        restingHeartRateBPM = values[.restingHeartRate]?.value
        walkingHeartRateAverageBPM = values[.walkingHeartRateAverage]?.value
        respiratoryRate = values[.respiratoryRate]?.value
        respiratoryRateMin = values[.respiratoryRate]?.minimum
        respiratoryRateMax = values[.respiratoryRate]?.maximum
        bloodGlucoseMgDl = values[.bloodGlucose]?.value
        bloodGlucoseMgDlMin = values[.bloodGlucose]?.minimum
        bloodGlucoseMgDlMax = values[.bloodGlucose]?.maximum
        sleepHours = values[.sleep]?.value
        sleepDeepHours = values[.sleep]?.deepHours
        sleepREMHours = values[.sleep]?.remHours
        sleepSource = values[.sleep]?.source
        weightKg = values[.weight]?.value
        menstrualFlow = cycle?.flow
        periodStart = cycle?.periodStart ?? false
        spotting = cycle?.spotting ?? false
    }
}

public enum MarkdownWriter {
    public static let schemaVersion = 1

    public static let readme = """
        # Vital Courier

        Vital Courier writes and owns everything in this folder. Any edit made here gets overwritten the next time the app exports, so keep your own notes somewhere else.

        - `json/<type>/<YYYY-MM>.json` holds every raw sample of one type for one month.
        - `daily/<YYYY-MM-DD>.md` holds one note per day with that day's values as properties.

        """

    public static func note(for summary: DailySummary) -> Data {
        var lines = ["---", "date: \(summary.day)"]
        // Truncated, not rounded: the Health app shows a fractional de-duplicated step sum without its fraction.
        if let steps = summary.steps { lines.append("vc_steps: \(Int(steps.rounded(.towardZero)))") }
        if let minutes = summary.exerciseMinutes { lines.append("vc_exercise_minutes: \(Int(minutes.rounded(.towardZero)))") }
        if let bpm = summary.restingHeartRateBPM { lines.append("vc_resting_hr_bpm: \(oneDecimal(bpm))") }
        if let bpm = summary.walkingHeartRateAverageBPM { lines.append("vc_walking_hr_avg: \(oneDecimal(bpm))") }
        // Each written on its own: a missing minimum or maximum never hides the average (Respiratory Rate Spec, Edge cases).
        if let breaths = summary.respiratoryRate { lines.append("vc_respiratory_rate: \(oneDecimal(breaths))") }
        if let breaths = summary.respiratoryRateMin { lines.append("vc_respiratory_rate_min: \(oneDecimal(breaths))") }
        if let breaths = summary.respiratoryRateMax { lines.append("vc_respiratory_rate_max: \(oneDecimal(breaths))") }
        // Whole numbers, rounded: mg/dL is read without decimals.
        if let milligrams = summary.bloodGlucoseMgDl { lines.append("vc_glucose_mg_dl: \(noDecimals(milligrams))") }
        if let milligrams = summary.bloodGlucoseMgDlMin { lines.append("vc_glucose_mg_dl_min: \(noDecimals(milligrams))") }
        if let milligrams = summary.bloodGlucoseMgDlMax { lines.append("vc_glucose_mg_dl_max: \(noDecimals(milligrams))") }
        if let hours = summary.sleepHours { lines.append("vc_sleep_hours: \(twoDecimals(hours))") }
        if let hours = summary.sleepDeepHours { lines.append("vc_sleep_deep_hours: \(twoDecimals(hours))") }
        if let hours = summary.sleepREMHours { lines.append("vc_sleep_rem_hours: \(twoDecimals(hours))") }
        if let source = summary.sleepSource { lines.append("vc_sleep_source: \(quoted(source))") }
        if let kilograms = summary.weightKg { lines.append("vc_weight_kg: \(oneDecimal(kilograms))") }
        // Flags are written only when true (Cycle Tracking Spec, Output).
        if let flow = summary.menstrualFlow { lines.append("vc_menstrual_flow: \(flow)") }
        if summary.periodStart { lines.append("vc_period_start: true") }
        if summary.spotting { lines.append("vc_spotting: true") }
        lines.append("vc_schema: \(schemaVersion)")
        lines.append("---")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// Fixed locale so the decimal separator is always `.`, whatever the device language.
    static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func noDecimals(_ number: Double) -> String { String(format: "%.0f", locale: posixLocale, number) }

    static func oneDecimal(_ number: Double) -> String { String(format: "%.1f", locale: posixLocale, number) }

    static func twoDecimals(_ number: Double) -> String { String(format: "%.2f", locale: posixLocale, number) }

    /// A double-quoted YAML scalar. Control characters are escaped so the line always parses and round-trips.
    static func quoted(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\u{0}"..."\u{1F}", "\u{7F}"..."\u{9F}":
                escaped += "\\x" + String(format: "%02X", locale: posixLocale, scalar.value)
            case "\u{FEFF}", "\u{FFFE}", "\u{FFFF}":
                escaped += "\\u" + String(format: "%04X", locale: posixLocale, scalar.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }
}
