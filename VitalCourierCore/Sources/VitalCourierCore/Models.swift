import Foundation

public enum HealthType: String, CaseIterable, Sendable, Codable {
    case steps
    case restingHeartRate
    case sleep
    case weight

    /// Folder name under `Vital Courier/json/`.
    public var folderName: String {
        switch self {
        case .steps: "steps"
        case .restingHeartRate: "resting-heart-rate"
        case .sleep: "sleep"
        case .weight: "weight"
        }
    }

    /// SI unit written to the JSON `unit` field. Sample values are stored in this unit.
    public var siUnit: String {
        switch self {
        case .steps: "count"
        case .restingHeartRate: "count/s"
        case .sleep: "category"
        case .weight: "kg"
        }
    }
}

public enum SampleValue: Sendable, Equatable {
    case quantity(Double)
    case category(String)
}

extension SampleValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .quantity(number)
        } else {
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

    public init(added: [HealthSample] = [], deletedUUIDs: [UUID] = [], newAnchor: Data? = nil) {
        self.added = added
        self.deletedUUIDs = deletedUUIDs
        self.newAnchor = newAnchor
    }
}
