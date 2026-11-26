import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct CycleTypesTests {
  @Test func cycleTypesJoinTheEnabledSetOnlyWhenSwitchedOn() {
    #expect(
      HealthType.enabledTypes(cycleTrackingEnabled: false) == [
        .steps, .exerciseMinutes, .activeEnergy, .walkingRunningDistance, .restingEnergy, .flightsClimbed,
        .standMinutes, .walkingSpeed, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .heartRateVariability,
        .cardioFitness, .respiratoryRate, .bloodGlucose, .bloodOxygen, .sleep, .weight, .wristTemperature,
      ])
    #expect(
      HealthType.enabledTypes(cycleTrackingEnabled: true) == [
        .steps, .exerciseMinutes, .activeEnergy, .walkingRunningDistance, .restingEnergy, .flightsClimbed,
        .standMinutes, .walkingSpeed, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .heartRateVariability,
        .cardioFitness, .respiratoryRate, .bloodGlucose, .bloodOxygen, .sleep, .weight, .wristTemperature,
        .menstrualFlow, .spotting,
      ])
    #expect(HealthType.baseTypes + HealthType.cycleTypes == HealthType.allCases)
  }

  @Test func cycleTypesAreCategoriesInTheirOwnFolders() {
    #expect(HealthType.menstrualFlow.folderName == "menstrual-flow")
    #expect(HealthType.spotting.folderName == "spotting")
    #expect(HealthType.menstrualFlow.siUnit == "category")
    #expect(HealthType.spotting.siUnit == "category")
  }
}
