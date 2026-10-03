import Foundation
import HealthKit
import VitalCourierCore

public enum HealthKitMappingError: Error, Equatable {
    case unexpectedSampleClass(String)
    case incompatibleUnit(String)
    case unreadableAnchor
}

/// Pure HealthKit ↔ core conversions. Nothing here touches `HKHealthStore`, so all of it is tested on the Mac.
public enum HealthKitMapping {
    public static func sampleType(for type: HealthType) -> HKSampleType {
        switch type {
        case .steps: HKQuantityType(.stepCount)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .weight: HKQuantityType(.bodyMass)
        }
    }

    /// The four types Vital Courier asks to read. Nothing else (design §2; HIG HealthKit page).
    public static var readTypes: Set<HKObjectType> {
        Set(HealthType.allCases.map { sampleType(for: $0) })
    }

    /// The SI unit samples are stored in (`HealthType.siUnit`). Sleep is a category, so it has none.
    public static func storedUnit(for type: HealthType) -> HKUnit? {
        switch type {
        case .steps: .count()
        case .restingHeartRate: .count().unitDivided(by: .second())
        case .weight: .gramUnit(with: .kilo)
        case .sleep: nil
        }
    }

    /// Daily values (spec, Daily values): steps as a count, resting heart rate in beats per minute.
    public static func statisticUnit(for type: HealthType) -> HKUnit? {
        switch type {
        case .steps: .count()
        case .restingHeartRate: .count().unitDivided(by: .minute())
        case .weight, .sleep: nil
        }
    }

    /// `doubleValue(for:)` raises an Objective-C exception on an incompatible unit, so the check comes first.
    public static func storedValue(_ quantity: HKQuantity, for type: HealthType) throws -> Double {
        guard let unit = storedUnit(for: type), quantity.is(compatibleWith: unit) else {
            throw HealthKitMappingError.incompatibleUnit("\(type.rawValue): \(quantity)")
        }
        return quantity.doubleValue(for: unit)
    }

    /// The strings `SleepAggregator` and the JSON use.
    public static func sleepValueName(rawValue: Int) -> String {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return "unknown(\(rawValue))" }
        switch value {
        case .inBed: return "inBed"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake: return "awake"
        case .asleepCore: return "asleepCore"
        case .asleepDeep: return "asleepDeep"
        case .asleepREM: return "asleepREM"
        @unknown default: return "unknown(\(rawValue))"
        }
    }

    public static func stringMetadata(_ metadata: [String: Any]?) -> [String: String] {
        guard let metadata else { return [:] }
        var strings: [String: String] = [:]
        for (key, value) in metadata {
            strings[key] = string(from: value)
        }
        return strings
    }

    static func string(from value: Any) -> String {
        switch value {
        case let text as String: text
        case let date as Date: date.formatted(.iso8601)
        case let quantity as HKQuantity: quantity.description
        case let number as NSNumber: number.stringValue
        default: String(describing: value)
        }
    }

    /// `HKMetadataKeyTimeZone`, when present and a real zone (spec, Day assignment).
    public static func timeZoneIdentifier(in metadata: [String: Any]?) -> String? {
        guard let identifier = metadata?[HKMetadataKeyTimeZone] as? String, TimeZone(identifier: identifier) != nil else { return nil }
        return identifier
    }

    public static func makeSample(
        uuid: UUID,
        type: HealthType,
        start: Date,
        end: Date,
        value: SampleValue,
        sourceName: String,
        deviceName: String?,
        metadata: [String: Any]?
    ) -> HealthSample {
        HealthSample(
            uuid: uuid,
            type: type,
            start: start,
            end: end,
            value: value,
            source: sourceName,
            device: deviceName,
            metadata: stringMetadata(metadata),
            timeZoneIdentifier: timeZoneIdentifier(in: metadata)
        )
    }

    public static func anchorData(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    public static func queryAnchor(from data: Data) throws -> HKQueryAnchor {
        guard let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
            throw HealthKitMappingError.unreadableAnchor
        }
        return anchor
    }
}
