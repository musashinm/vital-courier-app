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

    @Test func bloodGlucoseHasItsOwnHomeRowNameAndSymbol() {
        #expect(HealthType.bloodGlucose.displayName == String(localized: "Blood glucose"))
        #expect(HealthType.bloodGlucose.symbolName == "waveform.path.ecg.rectangle.fill")
    }

    @Test func everyTypeHasItsOwnHomeRowSymbol() {
        #expect(Set(HealthType.allCases.map(\.symbolName)).count == HealthType.allCases.count)
    }
}
