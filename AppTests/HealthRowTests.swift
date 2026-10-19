import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

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

  @Test func bloodOxygenSharesTheLungsSymbol() {
    #expect(HealthType.bloodOxygen.displayName == String(localized: "Blood oxygen"))
    #expect(HealthType.bloodOxygen.symbolName == "lungs.fill")
    #expect(HealthType.bloodOxygen.symbolName == HealthType.respiratoryRate.symbolName)
  }

  @Test func walkingHeartRateAverageSharesTheRestingHeartRateSymbol() {
    #expect(HealthType.walkingHeartRateAverage.displayName == String(localized: "Walking heart rate average"))
    #expect(HealthType.walkingHeartRateAverage.symbolName == "heart.fill")
    #expect(HealthType.walkingHeartRateAverage.symbolName == HealthType.restingHeartRate.symbolName)
  }

  @Test func heartRateSharesTheHeartSymbol() {
    #expect(HealthType.heartRate.displayName == String(localized: "Heart rate"))
    #expect(HealthType.heartRate.symbolName == "heart.fill")
    #expect(HealthType.heartRate.symbolName == HealthType.restingHeartRate.symbolName)
  }

  @Test func everyOtherTypeHasItsOwnHomeRowSymbol() {
    // The three heart rates share heart.fill and blood oxygen shares respiratory rate's lungs.fill, as in Apple's Health app; nothing else may.
    let typesWithTheirOwnSymbol = HealthType.allCases.filter {
      $0 != .walkingHeartRateAverage && $0 != .heartRate && $0 != .bloodOxygen
    }
    #expect(Set(typesWithTheirOwnSymbol.map(\.symbolName)).count == typesWithTheirOwnSymbol.count)
  }
}
