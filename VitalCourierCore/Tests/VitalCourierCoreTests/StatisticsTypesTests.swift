import Testing

@testable import VitalCourierCore

@Suite struct StatisticsTypesTests {
  @Test func statisticsAggregationClassifiesEveryType() {
    #expect(HealthType.steps.statisticsAggregation == .sum)
    #expect(HealthType.exerciseMinutes.statisticsAggregation == .sum)
    #expect(HealthType.activeEnergy.statisticsAggregation == .sum)
    #expect(HealthType.walkingRunningDistance.statisticsAggregation == .sum)
    #expect(HealthType.restingEnergy.statisticsAggregation == .sum)
    #expect(HealthType.flightsClimbed.statisticsAggregation == .sum)
    #expect(HealthType.standMinutes.statisticsAggregation == .sum)
    #expect(HealthType.walkingSpeed.statisticsAggregation == .average)
    #expect(HealthType.walkingStepLength.statisticsAggregation == .average)
    #expect(HealthType.walkingAsymmetry.statisticsAggregation == .average)
    #expect(HealthType.doubleSupportTime.statisticsAggregation == .average)
    #expect(HealthType.cardioFitness.statisticsAggregation == .average)
    #expect(HealthType.restingHeartRate.statisticsAggregation == .average)
    #expect(HealthType.walkingHeartRateAverage.statisticsAggregation == .average)
    #expect(HealthType.heartRate.statisticsAggregation == .averageMinMax)
    #expect(HealthType.heartRateVariability.statisticsAggregation == .averageMinMax)
    #expect(HealthType.respiratoryRate.statisticsAggregation == .averageMinMax)
    #expect(HealthType.bloodGlucose.statisticsAggregation == .averageMinMax)
    #expect(HealthType.bloodOxygen.statisticsAggregation == .averageMinMax)
    #expect(HealthType.sleep.statisticsAggregation == nil)
    #expect(HealthType.weight.statisticsAggregation == nil)
    #expect(HealthType.wristTemperature.statisticsAggregation == nil)
    #expect(HealthType.menstrualFlow.statisticsAggregation == nil)
    #expect(HealthType.spotting.statisticsAggregation == nil)
  }

  @Test func walkingHeartRateAverageIsStoredPerSecond() {
    #expect(HealthType.walkingHeartRateAverage.folderName == "walking-heart-rate-average")
    #expect(HealthType.walkingHeartRateAverage.siUnit == "count/s")
  }

  @Test func exactlyTheNineteenStatisticsTypesUseTheStatisticsQuery() {
    #expect(
      HealthType.allCases.filter(\.usesStatisticsQuery) == [
        .steps, .exerciseMinutes, .activeEnergy, .walkingRunningDistance, .restingEnergy, .flightsClimbed,
        .standMinutes, .walkingSpeed, .walkingStepLength, .walkingAsymmetry, .doubleSupportTime, .restingHeartRate,
        .walkingHeartRateAverage, .heartRate, .heartRateVariability, .cardioFitness, .respiratoryRate, .bloodGlucose,
        .bloodOxygen,
      ])
  }

  @Test func exerciseMinutesIsStoredInSeconds() {
    #expect(HealthType.exerciseMinutes.folderName == "exercise-minutes")
    #expect(HealthType.exerciseMinutes.siUnit == "s")
  }

  @Test func activeEnergyIsStoredInJoules() {
    #expect(HealthType.activeEnergy.folderName == "active-energy")
    #expect(HealthType.activeEnergy.siUnit == "J")
  }

  @Test func restingEnergyIsStoredInJoules() {
    #expect(HealthType.restingEnergy.folderName == "resting-energy")
    #expect(HealthType.restingEnergy.siUnit == "J")
  }

  @Test func flightsClimbedIsStoredAsACount() {
    #expect(HealthType.flightsClimbed.folderName == "flights-climbed")
    #expect(HealthType.flightsClimbed.siUnit == "count")
  }

  @Test func standMinutesIsStoredInSeconds() {
    #expect(HealthType.standMinutes.folderName == "stand-minutes")
    #expect(HealthType.standMinutes.siUnit == "s")
  }

  @Test func cardioFitnessIsStoredInMillilitresPerKilogramMinute() {
    #expect(HealthType.cardioFitness.folderName == "cardio-fitness")
    #expect(HealthType.cardioFitness.siUnit == "ml/(kg*min)")
  }

  @Test func walkingSpeedIsStoredInMetresPerSecond() {
    #expect(HealthType.walkingSpeed.folderName == "walking-speed")
    #expect(HealthType.walkingSpeed.siUnit == "m/s")
  }

  @Test func walkingStepLengthIsStoredInMetres() {
    #expect(HealthType.walkingStepLength.folderName == "walking-step-length")
    #expect(HealthType.walkingStepLength.siUnit == "m")
  }

  @Test func walkingAsymmetryIsStoredAsAFraction() {
    #expect(HealthType.walkingAsymmetry.folderName == "walking-asymmetry")
    #expect(HealthType.walkingAsymmetry.siUnit == "%")
  }

  @Test func doubleSupportTimeIsStoredAsAFraction() {
    #expect(HealthType.doubleSupportTime.folderName == "double-support-time")
    #expect(HealthType.doubleSupportTime.siUnit == "%")
  }

  @Test func wristTemperatureIsStoredInCelsius() {
    #expect(HealthType.wristTemperature.folderName == "wrist-temperature")
    #expect(HealthType.wristTemperature.siUnit == "degC")
    #expect(!HealthType.wristTemperature.usesStatisticsQuery)
  }

  @Test func walkingRunningDistanceIsStoredInMetres() {
    #expect(HealthType.walkingRunningDistance.folderName == "walking-running-distance")
    #expect(HealthType.walkingRunningDistance.siUnit == "m")
  }

  @Test func heartRateVariabilityIsStoredInSeconds() {
    #expect(HealthType.heartRateVariability.folderName == "heart-rate-variability")
    #expect(HealthType.heartRateVariability.siUnit == "s")
  }

  @Test func heartRateIsStoredPerSecond() {
    #expect(HealthType.heartRate.folderName == "heart-rate")
    #expect(HealthType.heartRate.siUnit == "count/s")
  }

  @Test func respiratoryRateIsStoredPerSecond() {
    #expect(HealthType.respiratoryRate.folderName == "respiratory-rate")
    #expect(HealthType.respiratoryRate.siUnit == "count/s")
  }

  @Test func bloodOxygenIsStoredAsAFractionLabelledPercent() {
    #expect(HealthType.bloodOxygen.folderName == "blood-oxygen")
    #expect(HealthType.bloodOxygen.siUnit == "%")
  }

  @Test func bloodGlucoseIsStoredInGramsPerLiter() {
    #expect(HealthType.bloodGlucose.folderName == "blood-glucose")
    #expect(HealthType.bloodGlucose.siUnit == "g/L")
  }
}
