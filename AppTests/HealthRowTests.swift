import Foundation
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite struct HealthRowTests {
    @Test func exerciseMinutesHasItsOwnHomeRowNameAndSymbol() {
        #expect(HealthType.exerciseMinutes.displayName == String(localized: "Exercise minutes"))
        #expect(HealthType.exerciseMinutes.symbolName == "figure.run")
    }
}
