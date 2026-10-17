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

        enum CodingKeys: String, CodingKey {
            case uuid, start, end, value, source, device, metadata
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uuid, forKey: .uuid)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(value, forKey: .value)
            try container.encode(source, forKey: .source)
            try container.encode(device, forKey: .device)
            try container.encode(metadata, forKey: .metadata)
        }
    }

    public static func monthFile(type: HealthType, monthKey: String, samples: [HealthSample], timeZone: TimeZone, generatedAt: Date) throws -> Data {
        guard let firstDay = DayKey(monthKey + "-01"), (1...12).contains(firstDay.month) else {
            throw JSONWriterError.invalidMonthKey(monthKey)
        }
        let periodStart = firstDay.interval(in: timeZone).start
        let periodEnd = DayKey.calendar(in: timeZone).date(byAdding: .month, value: 1, to: periodStart)!
        let ordered = samples.sorted { ($0.start, $0.uuid.uuidString) < ($1.start, $1.uuid.uuidString) }
        var formatters = FormatterCache()
        let file = MonthFile(
            schemaVersion: schemaVersion,
            type: type.rawValue,
            unit: type.siUnit,
            period: Period(start: formatters.string(from: periodStart, in: timeZone), end: formatters.string(from: periodEnd, in: timeZone), timeZone: timeZone.identifier),
            generatedAt: formatters.string(from: generatedAt, in: timeZone),
            samples: ordered.map { sample in
                let sampleZone = DayAssigner.zone(for: sample, fallback: timeZone)
                return SampleEntry(
                    uuid: sample.uuid.uuidString,
                    start: formatters.string(from: sample.start, in: sampleZone, fractionalSeconds: true),
                    end: formatters.string(from: sample.end, in: sampleZone, fractionalSeconds: true),
                    value: sample.value,
                    source: sample.source,
                    device: sample.device,
                    metadata: sample.metadata
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    /// Formatters are costly to create and a heart rate month holds tens of thousands of samples,
    /// so one `monthFile` call builds each (zone, fractional seconds) formatter once and reuses it.
    /// It lives on the stack of that call rather than in a static, to stay free of shared mutable state.
    struct FormatterCache {
        private struct Key: Hashable {
            let timeZoneIdentifier: String
            let fractionalSeconds: Bool
        }

        private var formatters: [Key: ISO8601DateFormatter] = [:]

        mutating func string(from date: Date, in timeZone: TimeZone, fractionalSeconds: Bool = false) -> String {
            let key = Key(timeZoneIdentifier: timeZone.identifier, fractionalSeconds: fractionalSeconds)
            if let cached = formatters[key] {
                return cached.string(from: date)
            }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = timeZone
            formatter.formatOptions = fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            formatters[key] = formatter
            return formatter.string(from: date)
        }
    }
}
