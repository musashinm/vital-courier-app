import Testing
@testable import VitalCourierCore

@Suite struct ObservedTypesTests {
    @Test func observedTypesKeepTheEnabledOrderAndLeaveOutTypesNotAskedAbout() {
        let enabled = HealthType.enabledTypes(cycleTrackingEnabled: true)

        let observed = HealthType.observedTypes(enabled: enabled, askedAbout: [.spotting, .weight, .steps])

        #expect(observed == [.steps, .weight, .spotting])
    }

    @Test func anAskedTypeThatIsNotEnabledIsNotObserved() {
        let enabled = HealthType.enabledTypes(cycleTrackingEnabled: false)

        let observed = HealthType.observedTypes(enabled: enabled, askedAbout: Set(HealthType.allCases))

        #expect(observed == enabled)
    }
}
