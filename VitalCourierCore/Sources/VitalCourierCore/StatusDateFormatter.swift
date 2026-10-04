import Foundation

public struct RunMonthGroup: Equatable, Sendable, Identifiable {
    public let title: String
    public let runs: [RunRecord]
    public var id: String { title }
}

/// Dates in the app's copy: "today at 8:16 AM", "yesterday", "Sep 24". Names are English (the app is English only); the locale only picks a 12- or 24-hour clock.
public struct StatusDateFormatter: Sendable {
    public let timeZone: TimeZone
    public let locale: Locale

    public init(timeZone: TimeZone = .current, locale: Locale = .current) {
        self.timeZone = timeZone
        self.locale = locale
    }

    public func time(_ date: Date) -> String {
        // ICU puts a narrow no-break space before AM/PM; the design copy uses a plain space.
        let pattern = (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        return format(date, pattern: pattern)
    }

    public func day(_ day: DayKey, today: DayKey) -> String {
        if day == today { return "today" }
        if day == today.adding(days: -1) { return "yesterday" }
        return format(day.interval(in: timeZone).start, pattern: day.year == today.year ? "MMM d" : "MMM d, yyyy")
    }

    public func moment(_ date: Date, now: Date) -> String {
        "\(day(DayKey(date: date, timeZone: timeZone), today: DayKey(date: now, timeZone: timeZone))) at \(time(date))"
    }

    /// Run detail: "Oct 3, 2026 at 8:16 AM".
    public func fullMoment(_ date: Date) -> String {
        "\(format(date, pattern: "MMM d, yyyy")) at \(time(date))"
    }

    public func month(_ date: Date) -> String {
        format(date, pattern: "LLLL yyyy")
    }

    /// Consecutive runs of the same month, in the order given (newest first from the store).
    public func monthGroups(_ runs: [RunRecord]) -> [RunMonthGroup] {
        var groups: [RunMonthGroup] = []
        for run in runs {
            let title = month(run.startedAt)
            if let last = groups.last, last.title == title {
                groups[groups.count - 1] = RunMonthGroup(title: title, runs: last.runs + [run])
            } else {
                groups.append(RunMonthGroup(title: title, runs: [run]))
            }
        }
        return groups
    }

    public static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
