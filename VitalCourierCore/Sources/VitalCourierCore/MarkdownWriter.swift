import Foundation

public struct DailySummary: Equatable, Sendable {
    public var day: DayKey
    public var steps: Double?
    public var restingHeartRateBPM: Double?
    public var sleepHours: Double?
    public var sleepDeepHours: Double?
    public var sleepREMHours: Double?
    public var sleepSource: String?
    public var weightKg: Double?

    public init(day: DayKey) {
        self.day = day
    }

    public init(day: DayKey, values: [HealthType: DailyValue]) {
        self.day = day
        steps = values[.steps]?.value
        restingHeartRateBPM = values[.restingHeartRate]?.value
        sleepHours = values[.sleep]?.value
        sleepDeepHours = values[.sleep]?.deepHours
        sleepREMHours = values[.sleep]?.remHours
        sleepSource = values[.sleep]?.source
        weightKg = values[.weight]?.value
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
        if let steps = summary.steps { lines.append("vc_steps: \(Int(steps.rounded()))") }
        if let bpm = summary.restingHeartRateBPM { lines.append("vc_resting_hr_bpm: \(oneDecimal(bpm))") }
        if let hours = summary.sleepHours { lines.append("vc_sleep_hours: \(twoDecimals(hours))") }
        if let hours = summary.sleepDeepHours { lines.append("vc_sleep_deep_hours: \(twoDecimals(hours))") }
        if let hours = summary.sleepREMHours { lines.append("vc_sleep_rem_hours: \(twoDecimals(hours))") }
        if let source = summary.sleepSource { lines.append("vc_sleep_source: \(quoted(source))") }
        if let kilograms = summary.weightKg { lines.append("vc_weight_kg: \(oneDecimal(kilograms))") }
        lines.append("vc_schema: \(schemaVersion)")
        lines.append("---")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func oneDecimal(_ number: Double) -> String { String(format: "%.1f", number) }

    static func twoDecimals(_ number: Double) -> String { String(format: "%.2f", number) }

    /// A double-quoted YAML scalar.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
