import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct CycleTypesTests {
  @Test func cycleTypesJoinTheEnabledSetOnlyWhenSwitchedOn() {
    #expect(
      HealthType.enabledTypes(cycleTrackingEnabled: false) == [
        .steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate,
        .bloodGlucose, .bloodOxygen, .sleep, .weight,
      ])
    #expect(
      HealthType.enabledTypes(cycleTrackingEnabled: true) == [
        .steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate,
        .bloodGlucose, .bloodOxygen, .sleep, .weight, .menstrualFlow, .spotting,
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
