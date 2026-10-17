import HealthKit
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite @MainActor struct ObserverRegistrationTests {
    @Test func heartRateWakesTheAppAtMostHourlyAndEveryOtherTypeImmediately() {
        #expect(ObserverRegistration.backgroundDeliveryFrequency(for: .heartRate) == .hourly)
        for type in HealthType.allCases where type != .heartRate {
            #expect(ObserverRegistration.backgroundDeliveryFrequency(for: type) == .immediate)
        }
    }

    @Test func theQueryWatchesTheEnabledTypes() {
        let off = ObserverRegistration.descriptors(for: HealthType.enabledTypes(cycleTrackingEnabled: false)).map(\.sampleType)
        let on = ObserverRegistration.descriptors(for: HealthType.enabledTypes(cycleTrackingEnabled: true)).map(\.sampleType)
        #expect(off.count == 10)
        #expect(off.contains(HKQuantityType(.appleExerciseTime)))
        #expect(off.contains(HKQuantityType(.walkingHeartRateAverage)))
        #expect(off.contains(HKQuantityType(.heartRate)))
        #expect(off.contains(HKQuantityType(.respiratoryRate)))
        #expect(off.contains(HKQuantityType(.bloodGlucose)))
        #expect(off.contains(HKQuantityType(.oxygenSaturation)))
        #expect(!off.contains(HKCategoryType(.menstrualFlow)))
        #expect(on.count == 12)
        #expect(on.contains(HKCategoryType(.menstrualFlow)))
        #expect(on.contains(HKCategoryType(.intermenstrualBleeding)))
    }

    @Test func turningTrackingOnEnablesOnlyTheCycleTypesAndOffDisablesThem() {
        let off = HealthType.enabledTypes(cycleTrackingEnabled: false)
        let on = HealthType.enabledTypes(cycleTrackingEnabled: true)

        let turningOn = ObserverRegistration.deliveryChanges(from: off, to: on)
        #expect(turningOn.enable == [.menstrualFlow, .spotting])
        #expect(turningOn.disable.isEmpty)

        let turningOff = ObserverRegistration.deliveryChanges(from: on, to: off)
        #expect(turningOff.enable.isEmpty)
        #expect(turningOff.disable == [.menstrualFlow, .spotting])
    }

    @Test func theObserverWatchesOnlyTheTypesHealthHasBeenAskedAbout() {
        let settings = AppSettings(storage: InMemoryStorage())
        settings.cycleTrackingEnabled = true

        // Switch on, but nothing beyond the four original types was asked: no exercise, no cycle types.
        #expect(ObserverRegistration.typesToObserve(settings: settings) == [.steps, .restingHeartRate, .sleep, .weight])

        settings.recordHealthTypesAskedAbout(HealthType.enabledTypes(cycleTrackingEnabled: true))

        #expect(ObserverRegistration.typesToObserve(settings: settings) == HealthType.enabledTypes(cycleTrackingEnabled: true))
    }

    @Test func recordingANewTypeAddsOnlyThatTypeToTheObserver() {
        let settings = AppSettings(storage: InMemoryStorage())
        let beforeAsking = ObserverRegistration.typesToObserve(settings: settings)
        #expect(!ObserverRegistration.descriptors(for: beforeAsking).map(\.sampleType).contains(HKQuantityType(.appleExerciseTime)))

        settings.recordHealthTypesAskedAbout([.exerciseMinutes])
        let afterAsking = ObserverRegistration.typesToObserve(settings: settings)

        // A changed set is what lets `update` past its unchanged-types guard.
        #expect(afterAsking != beforeAsking)
        let changes = ObserverRegistration.deliveryChanges(from: beforeAsking, to: afterAsking)
        #expect(changes.enable == [.exerciseMinutes])
        #expect(changes.disable.isEmpty)
    }
}
