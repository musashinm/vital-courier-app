import Foundation
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite struct HealthRowTests {
    @Test func exerciseMinutesHasItsOwnHomeRowNameAndSymbol() {
        #expect(HealthType.exerciseMinutes.displayName == String(localized: "Exercise minutes"))
        #expect(HealthType.exerciseMinutes.symbolName == "figure.run")
    }

    @Test func respiratoryRateHasItsOwnHomeRowNameAndSymbol() {
        #expect(HealthType.respiratoryRate.displayName == String(localized: "Respiratory rate"))
        #expect(HealthType.respiratoryRate.symbolName == "lungs.fill")
    }
}
