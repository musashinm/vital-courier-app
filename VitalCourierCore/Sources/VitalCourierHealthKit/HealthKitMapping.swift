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
    case .exerciseMinutes: HKQuantityType(.appleExerciseTime)
    case .restingHeartRate: HKQuantityType(.restingHeartRate)
    case .walkingHeartRateAverage: HKQuantityType(.walkingHeartRateAverage)
    case .heartRate: HKQuantityType(.heartRate)
    case .respiratoryRate: HKQuantityType(.respiratoryRate)
    case .bloodGlucose: HKQuantityType(.bloodGlucose)
    case .bloodOxygen: HKQuantityType(.oxygenSaturation)
    case .sleep: HKCategoryType(.sleepAnalysis)
    case .weight: HKQuantityType(.bodyMass)
    case .menstrualFlow: HKCategoryType(.menstrualFlow)
    case .spotting: HKCategoryType(.intermenstrualBleeding)
    }
  }

  /// The types Vital Courier asks to read: the base types, plus the cycle types while Cycle tracking is on. Nothing else (design §2; HIG HealthKit page).
  public static func readTypes(for types: [HealthType]) -> Set<HKObjectType> {
    Set(types.map { sampleType(for: $0) })
  }

  /// The base types, asked for during onboarding.
  public static var readTypes: Set<HKObjectType> {
    readTypes(for: HealthType.baseTypes)
  }

  /// The SI unit samples are stored in (`HealthType.siUnit`). Categories have none.
  public static func storedUnit(for type: HealthType) -> HKUnit? {
    switch type {
    case .steps: .count()
    case .exerciseMinutes: .second()
    case .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate: .count().unitDivided(by: .second())
    case .bloodGlucose: .gram().unitDivided(by: .liter())
    case .bloodOxygen: .percent()
    case .weight: .gramUnit(with: .kilo)
    case .sleep, .menstrualFlow, .spotting: nil
    }
  }

  /// Daily values (spec, Daily values): steps as a count, exercise in minutes, resting heart rate and walking heart rate average in beats per minute, heart rate in beats per minute (average, minimum and maximum), respiratory rate in breaths per minute (average, minimum and maximum), blood glucose in mg/dL (average, minimum and maximum), blood oxygen as a 0–1 fraction (average, minimum and maximum; the note scales it to percent).
  public static func statisticUnit(for type: HealthType) -> HKUnit? {
    switch type {
    case .steps: .count()
    case .exerciseMinutes: .minute()
    case .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate: .count().unitDivided(by: .minute())
    case .bloodGlucose: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    case .bloodOxygen: .percent()
    case .weight, .sleep, .menstrualFlow, .spotting: nil
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

  /// The string a category sample is stored and exported as. Only category types reach this.
  public static func categoryValueName(rawValue: Int, for type: HealthType) -> String {
    switch type {
    case .menstrualFlow: menstrualFlowValueName(rawValue: rawValue)
    case .spotting: rawValue == HKCategoryValue.notApplicable.rawValue ? "notApplicable" : "unknown(\(rawValue))"
    case .steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate,
      .bloodGlucose, .bloodOxygen, .sleep, .weight:
      sleepValueName(rawValue: rawValue)
    }
  }

  /// The strings the cycle daily rule and the JSON use (Cycle Tracking Spec, Types).
  public static func menstrualFlowValueName(rawValue: Int) -> String {
    guard let value = HKCategoryValueVaginalBleeding(rawValue: rawValue) else { return "unknown(\(rawValue))" }
    switch value {
    case .unspecified: return "unspecified"
    case .light: return "light"
    case .medium: return "medium"
    case .heavy: return "heavy"
    case HKCategoryValueVaginalBleeding.none: return "none"
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
    guard let identifier = metadata?[HKMetadataKeyTimeZone] as? String, TimeZone(identifier: identifier) != nil else {
      return nil
    }
    return identifier
  }

  // swiftlint:disable:next function_parameter_count - explicit parameters; bundling them is a separate refactor
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
