import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct HealthCategoryMappingTests {
  @Test func currentTypesMapToTheirAppleHealthCategory() {
    #expect(HealthType.steps.category == .activity)
    #expect(HealthType.exerciseMinutes.category == .activity)
    #expect(HealthType.activeEnergy.category == .activity)
    #expect(HealthType.walkingRunningDistance.category == .activity)
    #expect(HealthType.restingEnergy.category == .activity)
    #expect(HealthType.flightsClimbed.category == .activity)
    #expect(HealthType.standMinutes.category == .activity)
    #expect(HealthType.heartRateVariability.category == .heart)
    #expect(HealthType.weight.category == .bodyMeasurements)
    #expect(HealthType.menstrualFlow.category == .cycleTracking)
    #expect(HealthType.spotting.category == .cycleTracking)
    #expect(HealthType.restingHeartRate.category == .heart)
    #expect(HealthType.walkingHeartRateAverage.category == .heart)
    #expect(HealthType.heartRate.category == .heart)
    #expect(HealthType.respiratoryRate.category == .respiratory)
    #expect(HealthType.bloodOxygen.category == .respiratory)
    #expect(HealthType.sleep.category == .sleep)
    #expect(HealthType.bloodGlucose.category == .vitals)
  }

  @Test func categoriesFollowAppleHealthOrder() {
    #expect(
      HealthCategory.allCases == [
        .activity, .bodyMeasurements, .cycleTracking, .hearing, .heart, .mentalWellbeing, .mobility, .nutrition,
        .respiratory, .sleep, .symptoms, .vitals, .otherData,
      ])
  }

  @Test func categorySymbolsReuseCurrentTypeSymbols() {
    let expectedSymbols: [HealthCategory: String] = [
      .activity: "figure.walk", .bodyMeasurements: "scalemass.fill", .cycleTracking: "drop.fill", .hearing: "ear",
      .heart: "heart.fill", .mentalWellbeing: "brain.head.profile", .mobility: "figure.walk.motion",
      .nutrition: "fork.knife", .respiratory: "lungs.fill", .sleep: "bed.double.fill",
      .symptoms: "cross.case.fill", .vitals: "waveform.path.ecg.rectangle.fill", .otherData: "ellipsis.circle.fill",
    ]
    for category in HealthCategory.allCases {
      #expect(category.symbolName == expectedSymbols[category], "\(category)")
      let currentTypeSymbols = HealthType.allCases.filter { $0.category == category }.map(\.symbolName)
      if !currentTypeSymbols.isEmpty {
        #expect(currentTypeSymbols.contains(category.symbolName), "\(category)")
      }
    }
  }

  @Test func pendingFixtureMapsEveryIdentifierOnce() {
    let allIdentifiers = pendingIdentifiersByCategory.values.flatMap { $0 }
    #expect(allIdentifiers.count == 176)
    #expect(Set(allIdentifiers).count == 176)
    let expectedCounts: [HealthCategory: Int] = [
      .activity: 26, .bodyMeasurements: 8, .cycleTracking: 15, .hearing: 6, .heart: 14, .mentalWellbeing: 2,
      .mobility: 12, .nutrition: 39, .respiratory: 5, .sleep: 0, .symptoms: 39, .vitals: 1, .otherData: 9,
    ]
    for category in HealthCategory.allCases {
      #expect(pendingIdentifiersByCategory[category]?.count == expectedCounts[category], "\(category)")
    }
    let currentIdentifiers: Set<String> = [
      "stepCount", "appleExerciseTime", "bodyMass", "menstrualFlow", "intermenstrualBleeding", "restingHeartRate",
      "walkingHeartRateAverage", "heartRate", "respiratoryRate", "oxygenSaturation", "sleepAnalysis", "bloodGlucose",
      "activeEnergyBurned", "distanceWalkingRunning", "heartRateVariabilitySDNN", "basalEnergyBurned", "flightsClimbed",
      "appleStandTime",
    ]
    #expect(Set(allIdentifiers).isDisjoint(with: currentIdentifiers))
  }

  @Test func deferredFamiliesAreNotMapped() {
    let deferredNames: Set<String> = [
      "medication", "clinicalRecord", "visionPrescription", "dateOfBirth", "biologicalSex", "bloodType",
      "fitzpatrickSkinType", "wheelchairUse", "activityMoveMode",
    ]
    let allIdentifiers = Set(pendingIdentifiersByCategory.values.flatMap { $0 })
    #expect(allIdentifiers.isDisjoint(with: deferredNames))
  }

  @Test func spotChecksFollowTheHealthAppEvidence() {
    func category(of identifier: String) -> HealthCategory? {
      pendingIdentifiersByCategory.first { $0.value.contains(identifier) }?.key
    }
    #expect(category(of: "bloodPressureSystolic") == .heart)
    #expect(category(of: "vo2Max") == .heart)
    #expect(category(of: "underwaterDepth") == .activity)
    #expect(category(of: "appleSleepingBreathingDisturbances") == .respiratory)
    #expect(category(of: "appleSleepingWristTemperature") == .bodyMeasurements)
    #expect(category(of: "numberOfTimesFallen") == .otherData)
    #expect(category(of: "bodyTemperature") == .vitals)
  }

  @Test func categoryNamesAreLocalized() {
    let expectedNames: [(HealthCategory, [String])] = [
      (.activity, ["Activity", "Atividade"]),
      (.bodyMeasurements, ["Body Measurements", "Medidas corporais"]),
      (.cycleTracking, ["Cycle Tracking", "Acompanhamento do ciclo"]),
      (.hearing, ["Hearing", "Audição"]),
      (.heart, ["Heart", "Coração"]),
      (.mentalWellbeing, ["Mental Wellbeing", "Bem-estar mental"]),
      (.mobility, ["Mobility", "Mobilidade"]),
      (.nutrition, ["Nutrition", "Nutrição"]),
      (.respiratory, ["Respiratory", "Respiração"]),
      (.sleep, ["Sleep", "Sono"]),
      (.symptoms, ["Symptoms", "Sintomas"]),
      (.vitals, ["Vitals", "Sinais vitais"]),
      (.otherData, ["Other Data", "Outros dados"]),
    ]
    #expect(expectedNames.count == HealthCategory.allCases.count)
    for (category, names) in expectedNames {
      #expect(category.name(in: .english) == names[0])
      #expect(category.name(in: .portuguese) == names[1])
    }
  }
}
