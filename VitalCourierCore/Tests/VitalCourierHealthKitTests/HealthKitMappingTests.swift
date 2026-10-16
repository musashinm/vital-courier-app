import Foundation
import HealthKit
import Testing
import VitalCourierCore
@testable import VitalCourierHealthKit

private func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

@Suite struct HealthKitMappingTests {
    @Test func theBaseTypesMapToTheirHealthKitTypes() {
        #expect(HealthKitMapping.sampleType(for: .steps) == HKQuantityType(.stepCount))
        #expect(HealthKitMapping.sampleType(for: .restingHeartRate) == HKQuantityType(.restingHeartRate))
        #expect(HealthKitMapping.sampleType(for: .sleep) == HKCategoryType(.sleepAnalysis))
        #expect(HealthKitMapping.sampleType(for: .weight) == HKQuantityType(.bodyMass))
        #expect(HealthKitMapping.readTypes.count == 8)
    }

    @Test func samplesAreStoredInSIUnits() throws {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        #expect(try HealthKitMapping.storedValue(HKQuantity(unit: perMinute, doubleValue: 60), for: .restingHeartRate) == 1)
        #expect(try HealthKitMapping.storedValue(HKQuantity(unit: .count(), doubleValue: 812), for: .steps) == 812)
        let kilograms = try HealthKitMapping.storedValue(HKQuantity(unit: .pound(), doubleValue: 154.324), for: .weight)
        #expect(abs(kilograms - 70) < 0.001)
    }

    @Test func aQuantityInTheWrongUnitIsAnErrorNotACrash() {
        #expect(throws: HealthKitMappingError.self) {
            try HealthKitMapping.storedValue(HKQuantity(unit: .count(), doubleValue: 1), for: .weight)
        }
        #expect(throws: HealthKitMappingError.self) {
            try HealthKitMapping.storedValue(HKQuantity(unit: .count(), doubleValue: 1), for: .sleep)
        }
    }

    @Test func dailyStatisticsUseCountAndBeatsPerMinute() {
        let perSecond = HKQuantity(unit: .count().unitDivided(by: .second()), doubleValue: 1)
        #expect(HealthKitMapping.statisticUnit(for: .restingHeartRate).map { perSecond.doubleValue(for: $0) } == 60)
        #expect(HealthKitMapping.statisticUnit(for: .steps) == .count())
        #expect(HealthKitMapping.statisticUnit(for: .weight) == nil)
        #expect(HealthKitMapping.statisticUnit(for: .sleep) == nil)
    }

    @Test func sleepValuesUseTheCoreNames() {
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.inBed.rawValue) == "inBed")
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue) == "asleepUnspecified")
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.awake.rawValue) == "awake")
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue) == "asleepCore")
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == "asleepDeep")
        #expect(HealthKitMapping.sleepValueName(rawValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue) == "asleepREM")
        #expect(HealthKitMapping.sleepValueName(rawValue: 99) == "unknown(99)")
        #expect(SleepAggregator.asleepValues == ["asleepUnspecified", "asleepCore", "asleepDeep", "asleepREM"])
    }

    @Test func metadataBecomesStrings() {
        let metadata: [String: Any] = [
            HKMetadataKeyTimeZone: "America/Sao_Paulo",
            HKMetadataKeyWasUserEntered: NSNumber(value: true),
            "VCDate": date("2026-10-03T11:16:00Z"),
            "VCQuantity": HKQuantity(unit: .count(), doubleValue: 5),
        ]

        let strings = HealthKitMapping.stringMetadata(metadata)

        #expect(strings[HKMetadataKeyTimeZone] == "America/Sao_Paulo")
        #expect(strings[HKMetadataKeyWasUserEntered] == "1")
        #expect(strings["VCDate"] == "2026-10-03T11:16:00Z")
        #expect(strings["VCQuantity"]?.contains("5") == true)
        #expect(HealthKitMapping.stringMetadata(nil) == [:])
    }

    @Test func onlyAValidTimeZoneKeyIsKept() {
        #expect(HealthKitMapping.timeZoneIdentifier(in: [HKMetadataKeyTimeZone: "Europe/Lisbon"]) == "Europe/Lisbon")
        #expect(HealthKitMapping.timeZoneIdentifier(in: [HKMetadataKeyTimeZone: "Mars/Base"]) == nil)
        #expect(HealthKitMapping.timeZoneIdentifier(in: [:]) == nil)
        #expect(HealthKitMapping.timeZoneIdentifier(in: nil) == nil)
    }

    @Test func makeSampleCarriesSourceDeviceMetadataAndZone() {
        let uuid = UUID()
        let sample = HealthKitMapping.makeSample(
            uuid: uuid, type: .sleep,
            start: date("2026-10-03T02:00:00Z"), end: date("2026-10-03T03:00:00Z"),
            value: .category("asleepREM"), sourceName: "Apple Watch", deviceName: "Watch",
            metadata: [HKMetadataKeyTimeZone: "America/Sao_Paulo"]
        )

        #expect(sample == HealthSample(
            uuid: uuid, type: .sleep,
            start: date("2026-10-03T02:00:00Z"), end: date("2026-10-03T03:00:00Z"),
            value: .category("asleepREM"), source: "Apple Watch", device: "Watch",
            metadata: [HKMetadataKeyTimeZone: "America/Sao_Paulo"], timeZoneIdentifier: "America/Sao_Paulo"
        ))
    }

    @Test func anchorsRoundTripThroughData() throws {
        let data = try HealthKitMapping.anchorData(HKQueryAnchor(fromValue: 42))

        let decoded = try HealthKitMapping.queryAnchor(from: data)

        #expect(try HealthKitMapping.anchorData(decoded) == data)
        #expect(throws: (any Error).self) { try HealthKitMapping.queryAnchor(from: Data([1, 2, 3])) }
    }

    @Test func cycleTypesMapToTheirHealthKitTypes() {
        #expect(HealthKitMapping.sampleType(for: .menstrualFlow) == HKCategoryType(.menstrualFlow))
        #expect(HealthKitMapping.sampleType(for: .spotting) == HKCategoryType(.intermenstrualBleeding))
        #expect(HealthKitMapping.readTypes.count == 8)
        #expect(HealthKitMapping.readTypes(for: HealthType.enabledTypes(cycleTrackingEnabled: true)).count == 10)
        #expect(HealthKitMapping.storedUnit(for: .menstrualFlow) == nil)
        #expect(HealthKitMapping.statisticUnit(for: .spotting) == nil)
    }

    @Test func exerciseMinutesMapsToAppleExerciseTime() {
        #expect(HealthKitMapping.sampleType(for: .exerciseMinutes) == HKQuantityType(.appleExerciseTime))
        #expect(HealthKitMapping.storedUnit(for: .exerciseMinutes) == .second())
        #expect(HealthKitMapping.statisticUnit(for: .exerciseMinutes) == .minute())
        #expect(HealthKitMapping.readTypes.contains(HKQuantityType(.appleExerciseTime)))
    }

    @Test func anExerciseQuantityIsStoredInSeconds() throws {
        let halfHour = HKQuantity(unit: .minute(), doubleValue: 30)
        #expect(try HealthKitMapping.storedValue(halfHour, for: .exerciseMinutes) == 1800)
    }

    @Test func respiratoryRateMapsToItsHealthKitType() {
        let perSecond = HKUnit.count().unitDivided(by: .second())
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        #expect(HealthKitMapping.sampleType(for: .respiratoryRate) == HKQuantityType(.respiratoryRate))
        #expect(HealthKitMapping.storedUnit(for: .respiratoryRate) == perSecond)
        #expect(HealthKitMapping.statisticUnit(for: .respiratoryRate) == perMinute)
        #expect(HealthKitMapping.readTypes.contains(HKQuantityType(.respiratoryRate)))
    }

    @Test func aRespiratoryQuantityIsStoredPerSecond() throws {
        let fifteenBreathsPerMinute = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 15)
        #expect(try HealthKitMapping.storedValue(fifteenBreathsPerMinute, for: .respiratoryRate) == 0.25)
    }

    @Test func walkingHeartRateAverageMapsToItsHealthKitType() {
        let perSecond = HKUnit.count().unitDivided(by: .second())
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        #expect(HealthKitMapping.sampleType(for: .walkingHeartRateAverage) == HKQuantityType(.walkingHeartRateAverage))
        #expect(HealthKitMapping.storedUnit(for: .walkingHeartRateAverage) == perSecond)
        #expect(HealthKitMapping.statisticUnit(for: .walkingHeartRateAverage) == perMinute)
        #expect(HealthKitMapping.readTypes.contains(HKQuantityType(.walkingHeartRateAverage)))
    }

    @Test func aWalkingHeartRateQuantityIsStoredPerSecond() throws {
        let ninetyBeatsPerMinute = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 90)
        #expect(try HealthKitMapping.storedValue(ninetyBeatsPerMinute, for: .walkingHeartRateAverage) == 1.5)
    }

    @Test func bloodGlucoseMapsToItsHealthKitType() {
        let gramsPerLiter = HKUnit.gram().unitDivided(by: .liter())
        let milligramsPerDeciliter = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        #expect(HealthKitMapping.sampleType(for: .bloodGlucose) == HKQuantityType(.bloodGlucose))
        #expect(HealthKitMapping.storedUnit(for: .bloodGlucose) == gramsPerLiter)
        #expect(HealthKitMapping.statisticUnit(for: .bloodGlucose) == milligramsPerDeciliter)
        #expect(HealthKitMapping.readTypes.contains(HKQuantityType(.bloodGlucose)))
    }

    @Test func aMilligramPerDeciliterGlucoseQuantityIsStoredInGramsPerLiter() throws {
        let oneHundredFourMilligramsPerDeciliter = HKQuantity(unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), doubleValue: 104)
        let gramsPerLiter = try HealthKitMapping.storedValue(oneHundredFourMilligramsPerDeciliter, for: .bloodGlucose)
        #expect(abs(gramsPerLiter - 1.04) < 0.000001)
    }

    @Test func aMillimolarGlucoseQuantityIsStoredInGramsPerLiter() throws {
        // CGM apps may write mmol/L; HealthKit converts it through the glucose molar mass (180.15588 g/mol).
        let millimolesPerLiter = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
        let fiveMillimolesPerLiter = HKQuantity(unit: millimolesPerLiter, doubleValue: 5)
        let gramsPerLiter = try HealthKitMapping.storedValue(fiveMillimolesPerLiter, for: .bloodGlucose)
        #expect(abs(gramsPerLiter - 0.9007794) < 0.0001)
    }

    @Test func flowValuesBecomeTheirNames() {
        // HKCategoryValueVaginalBleeding raw values (iOS 18), the same as the deprecated HKCategoryValueMenstrualFlow.
        #expect(HealthKitMapping.categoryValueName(rawValue: 1, for: .menstrualFlow) == "unspecified")
        #expect(HealthKitMapping.categoryValueName(rawValue: 2, for: .menstrualFlow) == "light")
        #expect(HealthKitMapping.categoryValueName(rawValue: 3, for: .menstrualFlow) == "medium")
        #expect(HealthKitMapping.categoryValueName(rawValue: 4, for: .menstrualFlow) == "heavy")
        #expect(HealthKitMapping.categoryValueName(rawValue: 5, for: .menstrualFlow) == "none")
        #expect(HealthKitMapping.categoryValueName(rawValue: 99, for: .menstrualFlow) == "unknown(99)")
        #expect(HKCategoryValueVaginalBleeding.heavy.rawValue == 4)
    }

    @Test func spottingAndSleepKeepTheirOwnNames() {
        #expect(HealthKitMapping.categoryValueName(rawValue: HKCategoryValue.notApplicable.rawValue, for: .spotting) == "notApplicable")
        #expect(HealthKitMapping.categoryValueName(rawValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue, for: .sleep) == "asleepREM")
    }

    @Test func theCycleStartFlagIsStoredAsOne() {
        #expect(CycleDayRule.menstrualCycleStartMetadataKey == HKMetadataKeyMenstrualCycleStart)
        #expect(HealthKitMapping.stringMetadata([HKMetadataKeyMenstrualCycleStart: NSNumber(value: true)])[HKMetadataKeyMenstrualCycleStart] == "1")
    }
}
