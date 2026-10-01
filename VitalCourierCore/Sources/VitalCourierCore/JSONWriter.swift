import Foundation

public enum JSONWriterError: Error, Equatable {
    case invalidMonthKey(String)
}

public enum JSONWriter {
    public static let schemaVersion = 1

    struct MonthFile: Encodable {
        let schemaVersion: Int
        let type: String
        let unit: String
        let period: Period
        let generatedAt: String
        let samples: [SampleEntry]
    }

    struct Period: Encodable {
        let start: String
        let end: String
        let timeZone: String
    }

    struct SampleEntry: Encodable {
        let uuid: String
        let start: String
        let end: String
        let value: SampleValue
        let source: String
        let device: String?
        let metadata: [String: String]
    }

    public static func monthFile(type: HealthType, monthKey: String, samples: [HealthSample], timeZone: TimeZone, generatedAt: Date) throws -> Data {
        guard let firstDay = DayKey(monthKey + "-01"), (1...12).contains(firstDay.month) else {
            throw JSONWriterError.invalidMonthKey(monthKey)
        }
        let periodStart = firstDay.interval(in: timeZone).start
        let periodEnd = DayKey.calendar(in: timeZone).date(byAdding: .month, value: 1, to: periodStart)!
        let ordered = samples.sorted { ($0.start, $0.uuid.uuidString) < ($1.start, $1.uuid.uuidString) }
        let file = MonthFile(
            schemaVersion: schemaVersion,
            type: type.rawValue,
            unit: type.siUnit,
            period: Period(start: iso8601(periodStart, in: timeZone), end: iso8601(periodEnd, in: timeZone), timeZone: timeZone.identifier),
            generatedAt: iso8601(generatedAt, in: timeZone),
            samples: ordered.map { sample in
                let sampleZone = DayAssigner.zone(for: sample, fallback: timeZone)
                return SampleEntry(
                    uuid: sample.uuid.uuidString,
                    start: iso8601(sample.start, in: sampleZone),
                    end: iso8601(sample.end, in: sampleZone),
                    value: sample.value,
                    source: sample.source,
                    device: sample.device,
                    metadata: sample.metadata
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func iso8601(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
