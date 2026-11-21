import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct HealthRowTests {
  @Test func exerciseMinutesHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.exerciseMinutes.displayName == String(localized: "Exercise minutes"))
    #expect(HealthType.exerciseMinutes.symbolName == "figure.run")
  }

  @Test func activeEnergyHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.activeEnergy.displayName == String(localized: "Active energy"))
    #expect(HealthType.activeEnergy.symbolName == "flame.fill")
  }

  @Test func restingEnergySharesTheActiveEnergySymbol() {
    #expect(HealthType.restingEnergy.displayName == String(localized: "Resting energy"))
    #expect(HealthType.restingEnergy.symbolName == "flame.fill")
    #expect(HealthType.restingEnergy.symbolName == HealthType.activeEnergy.symbolName)
  }

  @Test func flightsClimbedHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.flightsClimbed.displayName == String(localized: "Flights climbed"))
    #expect(HealthType.flightsClimbed.symbolName == "figure.stairs")
  }

  @Test func standMinutesHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.standMinutes.displayName == String(localized: "Stand minutes"))
    #expect(HealthType.standMinutes.symbolName == "figure.stand")
  }

  @Test func walkingRunningDistanceSharesTheStepsSymbol() {
    #expect(HealthType.walkingRunningDistance.displayName == String(localized: "Walking + running distance"))
    #expect(HealthType.walkingRunningDistance.symbolName == "figure.walk")
    #expect(HealthType.walkingRunningDistance.symbolName == HealthType.steps.symbolName)
  }

  @Test func heartRateVariabilitySharesTheHeartSymbol() {
    #expect(HealthType.heartRateVariability.displayName == String(localized: "Heart rate variability"))
    #expect(HealthType.heartRateVariability.symbolName == "heart.fill")
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
    // The heart types share heart.fill, walking + running distance shares steps' figure.walk, resting energy shares active energy's flame.fill and blood oxygen shares respiratory rate's lungs.fill, as in Apple's Health app; nothing else may.
    let typesWithTheirOwnSymbol = HealthType.allCases.filter {
      $0 != .walkingHeartRateAverage && $0 != .heartRate && $0 != .bloodOxygen && $0 != .walkingRunningDistance
        && $0 != .heartRateVariability && $0 != .restingEnergy
    }
    #expect(Set(typesWithTheirOwnSymbol.map(\.symbolName)).count == typesWithTheirOwnSymbol.count)
  }
}
