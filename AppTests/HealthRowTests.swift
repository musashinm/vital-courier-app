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

  @Test func cardioFitnessSharesTheHeartSymbol() {
    #expect(HealthType.cardioFitness.displayName == String(localized: "Cardio fitness"))
    #expect(HealthType.cardioFitness.symbolName == "heart.fill")
    #expect(HealthType.cardioFitness.symbolName == HealthType.restingHeartRate.symbolName)
  }

  @Test func walkingSpeedHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.walkingSpeed.displayName == String(localized: "Walking speed"))
    #expect(HealthType.walkingSpeed.symbolName == "figure.walk.motion")
  }

  @Test func wristTemperatureHasItsOwnHomeRowNameAndSymbol() {
    #expect(HealthType.wristTemperature.displayName == String(localized: "Wrist temperature"))
    #expect(HealthType.wristTemperature.symbolName == "thermometer.medium")
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

  @Test func mobilityTypesShareTheWalkingSpeedSymbol() {
    #expect(HealthType.walkingStepLength.displayName == String(localized: "Walking step length"))
    #expect(HealthType.walkingAsymmetry.displayName == String(localized: "Walking asymmetry"))
    #expect(HealthType.doubleSupportTime.displayName == String(localized: "Double support time"))
    let brazilian = Locale(identifier: "pt_BR")
    #expect(
      String(localized: LocalizedStringResource("Walking step length", locale: brazilian)) == "Comprimento do passo")
    #expect(
      String(localized: LocalizedStringResource("Walking asymmetry", locale: brazilian)) == "Assimetria ao caminhar")
    #expect(
      String(localized: LocalizedStringResource("Double support time", locale: brazilian)) == "Tempo de apoio duplo")
    for type in [HealthType.walkingStepLength, .walkingAsymmetry, .doubleSupportTime] {
      #expect(type.symbolName == "figure.walk.motion")
      #expect(type.symbolName == HealthType.walkingSpeed.symbolName)
    }
  }

  @Test func everyOtherTypeHasItsOwnHomeRowSymbol() {
    // The heart types and cardio fitness share heart.fill, walking + running distance shares steps' figure.walk, resting energy shares active energy's flame.fill, blood oxygen shares respiratory rate's lungs.fill and the mobility types share walking speed's figure.walk.motion, as in Apple's Health app; nothing else may.
    let typesWithTheirOwnSymbol = HealthType.allCases.filter {
      $0 != .walkingHeartRateAverage && $0 != .heartRate && $0 != .bloodOxygen && $0 != .walkingRunningDistance
        && $0 != .heartRateVariability && $0 != .restingEnergy && $0 != .cardioFitness && $0 != .walkingStepLength
        && $0 != .walkingAsymmetry && $0 != .doubleSupportTime
    }
    #expect(Set(typesWithTheirOwnSymbol.map(\.symbolName)).count == typesWithTheirOwnSymbol.count)
  }
}
