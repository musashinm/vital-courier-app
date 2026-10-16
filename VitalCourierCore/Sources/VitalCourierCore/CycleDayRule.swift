import Foundation

/// The daily cycle values (Cycle Tracking Spec, Output): the heaviest flow of the day, whether any flow sample starts a period, and whether any spotting was logged.
public enum CycleDayRule {
    /// `HKMetadataKeyMenstrualCycleStart`, spelled out because Core doesn't import HealthKit. A HealthKit test checks it.
    public static let menstrualCycleStartMetadataKey = "HKMenstrualCycleStart"

    /// Lightest first. A value outside this list (one a later iOS adds) ranks below `none`, so it only shows when nothing else was logged.
    static let flowOrder = ["none", "unspecified", "light", "medium", "heavy"]

    public static func flowUpdate(from samples: [HealthSample]) -> CycleDayUpdate {
        let flows = samples.compactMap { sample -> String? in
            guard case .category(let name) = sample.value else { return nil }
            return name
        }
        let heaviest = flows.max { rank($0) < rank($1) }
        let periodStart = samples.contains { isCycleStart($0.metadata[menstrualCycleStartMetadataKey]) }
        return .flow(heaviest, periodStart: periodStart)
    }

    public static func spottingUpdate(from samples: [HealthSample]) -> CycleDayUpdate {
        .spotting(!samples.isEmpty)
    }

    static func rank(_ flow: String) -> Int {
        flowOrder.firstIndex(of: flow) ?? -1
    }

    /// HealthKit stores the flag as a Bool `NSNumber`, which `HealthKitMapping.stringMetadata` writes as "1".
    static func isCycleStart(_ text: String?) -> Bool {
        text == "1" || text == "true"
    }
}
