import HealthKit
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite @MainActor struct ObserverRegistrationTests {
    @Test func theQueryWatchesTheEnabledTypes() {
        let off = ObserverRegistration.descriptors(for: HealthType.enabledTypes(cycleTrackingEnabled: false)).map(\.sampleType)
        let on = ObserverRegistration.descriptors(for: HealthType.enabledTypes(cycleTrackingEnabled: true)).map(\.sampleType)
        #expect(off.count == 4)
        #expect(!off.contains(HKCategoryType(.menstrualFlow)))
        #expect(on.count == 6)
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
}
