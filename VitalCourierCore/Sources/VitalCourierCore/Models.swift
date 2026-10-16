import Foundation

public enum HealthType: String, CaseIterable, Sendable, Codable {
    case steps
    case exerciseMinutes
    case restingHeartRate
    case walkingHeartRateAverage
    case respiratoryRate
    case bloodGlucose
    case sleep
    case weight
    case menstrualFlow
    case spotting

    /// The types every install exports.
    public static let baseTypes: [HealthType] = [.steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate, .bloodGlucose, .sleep, .weight]
    /// Exported only while Cycle tracking is on (Cycle Tracking Spec).
    public static let cycleTypes: [HealthType] = [.menstrualFlow, .spotting]

    /// The types the app reads, observes, exports and lists.
    public static func enabledTypes(cycleTrackingEnabled: Bool) -> [HealthType] {
        cycleTrackingEnabled ? baseTypes + cycleTypes : baseTypes
    }

    /// The enabled types Health has been asked about, in enabled order: the ones the observer may watch.
    public static func observedTypes(enabled: [HealthType], askedAbout: Set<HealthType>) -> [HealthType] {
        enabled.filter(askedAbout.contains)
    }

    /// Folder name under `Vital Courier/json/`.
    public var folderName: String {
        switch self {
        case .steps: "steps"
        case .exerciseMinutes: "exercise-minutes"
        case .restingHeartRate: "resting-heart-rate"
        case .walkingHeartRateAverage: "walking-heart-rate-average"
        case .respiratoryRate: "respiratory-rate"
        case .bloodGlucose: "blood-glucose"
        case .sleep: "sleep"
        case .weight: "weight"
        case .menstrualFlow: "menstrual-flow"
        case .spotting: "spotting"
        }
    }

    /// SI unit written to the JSON `unit` field. Sample values are stored in this unit.
    public var siUnit: String {
        switch self {
        case .steps: "count"
        case .exerciseMinutes: "s"
        case .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate: "count/s"
        case .bloodGlucose: "g/L"
        case .sleep, .menstrualFlow, .spotting: "category"
        case .weight: "kg"
        }
    }

    /// How the daily value is built from HealthKit's statistics query; nil for types that don't use it. One exhaustive switch, so a new type has to be classified to compile (Exercise Minutes Spec, Statistics query).
    public var statisticsAggregation: StatisticsAggregation? {
        switch self {
        case .steps, .exerciseMinutes: .sum
        case .restingHeartRate, .walkingHeartRateAverage: .average
        case .respiratoryRate, .bloodGlucose: .averageMinMax
        case .sleep, .weight, .menstrualFlow, .spotting: nil
        }
    }

    /// The statistics query splits a sample across every day it overlaps, so these types dirty every overlapped day.
    public var usesStatisticsQuery: Bool { statisticsAggregation != nil }
}

public enum StatisticsAggregation: Sendable, Equatable {
    case sum
    case average
    /// The day's average plus its minimum and maximum, from one query (Respiratory Rate Spec, Statistics query).
    case averageMinMax
}

public enum SampleValue: Sendable, Equatable {
    case quantity(Double)
    case category(String)
}

extension SampleValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self = .quantity(try container.decode(Double.self))
        } catch DecodingError.typeMismatch {
            self = .category(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .quantity(let number): try container.encode(number)
        case .category(let text): try container.encode(text)
        }
    }
}

public struct HealthSample: Sendable, Equatable {
    public var uuid: UUID
    public var type: HealthType
    public var start: Date
    public var end: Date
    public var value: SampleValue
    public var source: String
    public var device: String?
    public var metadata: [String: String]
    /// From `HKMetadataKeyTimeZone` when HealthKit has it. Samples read back from `LocalStore` carry the zone their day was computed in.
    public var timeZoneIdentifier: String?

    public init(
        uuid: UUID,
        type: HealthType,
        start: Date,
        end: Date,
        value: SampleValue,
        source: String,
        device: String?,
        metadata: [String: String],
        timeZoneIdentifier: String?
    ) {
        self.uuid = uuid
        self.type = type
        self.start = start
        self.end = end
        self.value = value
        self.source = source
        self.device = device
        self.metadata = metadata
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct HealthChanges: Sendable, Equatable {
    public var added: [HealthSample]
    public var deletedUUIDs: [UUID]
    /// Nil when there is no anchor to save (Verify batches).
    public var newAnchor: Data?
    /// True when the source stopped at its batch limit: call `changes(for:since:)` again with `newAnchor`.
    public var hasMore: Bool

    public init(added: [HealthSample] = [], deletedUUIDs: [UUID] = [], newAnchor: Data? = nil, hasMore: Bool = false) {
        self.added = added
        self.deletedUUIDs = deletedUUIDs
        self.newAnchor = newAnchor
        self.hasMore = hasMore
    }
}
