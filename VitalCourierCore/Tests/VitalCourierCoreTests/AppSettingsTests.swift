import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct AppSettingsTests {
  @Test func valuesRoundTripAndNilClears() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    #expect(settings.folderBookmark == nil)
    #expect(settings.awaitingRereadAfterClear == false)
    #expect(settings.setupCompletedAt == nil)

    settings.folderBookmark = Data([1, 2])
    settings.folderDisplayPath = "iCloud Drive/Health"
    settings.folderLostError = "gone"
    settings.setupCompletedAt = date("2026-10-03T11:16:00Z")
    settings.awaitingRereadAfterClear = true

    let reread = AppSettings(storage: storage)
    #expect(reread.folderBookmark == Data([1, 2]))
    #expect(reread.folderDisplayPath == "iCloud Drive/Health")
    #expect(reread.folderLostError == "gone")
    #expect(reread.setupCompletedAt == date("2026-10-03T11:16:00Z"))
    #expect(reread.awaitingRereadAfterClear == true)

    reread.folderLostError = nil
    reread.awaitingRereadAfterClear = false
    #expect(settings.folderLostError == nil)
    #expect(settings.awaitingRereadAfterClear == false)
  }

  @Test func pendingSetupErrorsDefaultToEmptyAndRoundTrip() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    #expect(settings.pendingSetupErrors == [])

    settings.pendingSetupErrors = ["one", "two \"quoted\""]
    #expect(AppSettings(storage: storage).pendingSetupErrors == ["one", "two \"quoted\""])

    settings.pendingSetupErrors = []
    #expect(AppSettings(storage: storage).pendingSetupErrors == [])
  }

  @Test func undecodablePendingSetupErrorsAreSurfacedNotDropped() {
    let storage = InMemoryStorage()
    storage.set(Data("not json".utf8), forKey: AppSettings.Key.pendingSetupErrors)
    let entries = AppSettings(storage: storage).pendingSetupErrors
    #expect(entries.count == 1)
    #expect(entries[0].contains("not json"))
  }

  @Test func cycleTrackingIsOffUntilTurnedOn() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    #expect(settings.cycleTrackingEnabled == false)

    settings.cycleTrackingEnabled = true
    #expect(AppSettings(storage: storage).cycleTrackingEnabled == true)

    settings.cycleTrackingEnabled = false
    #expect(AppSettings(storage: storage).cycleTrackingEnabled == false)
  }

  @Test func healthTypesAskedAboutDefaultsToTheFourOriginalTypesWhateverTheSwitch() {
    let settings = AppSettings(storage: InMemoryStorage())
    #expect(settings.healthTypesAskedAbout == [.steps, .restingHeartRate, .sleep, .weight])

    settings.cycleTrackingEnabled = true

    #expect(settings.healthTypesAskedAbout == [.steps, .restingHeartRate, .sleep, .weight])
  }

  @Test func recordingHealthTypesAddsAndNeverRemoves() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)

    settings.recordHealthTypesAskedAbout([.exerciseMinutes])
    settings.recordHealthTypesAskedAbout([.steps])

    #expect(
      AppSettings(storage: storage).healthTypesAskedAbout == [
        .steps, .exerciseMinutes, .restingHeartRate, .sleep, .weight,
      ])
  }

  @Test func unknownAskedTypesAreIgnoredAndUnreadableDataFallsBackToTheDefault() throws {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)

    storage.set(
      try JSONEncoder().encode(["steps", "aTypeFromALaterVersion"]), forKey: AppSettings.Key.healthTypesAskedAbout)
    #expect(settings.healthTypesAskedAbout == [.steps])

    storage.set(Data("not json".utf8), forKey: AppSettings.Key.healthTypesAskedAbout)
    #expect(settings.healthTypesAskedAbout == [.steps, .restingHeartRate, .sleep, .weight])
  }

  @Test func aPersisted041AskedSetLeavesTheNewTypesUnobservedUntilRecorded() throws {
    // A 0.4.1 install persisted the thirteen base types; the new ones stay unobserved until the sheet is answered (Resting Energy, Flights and Stand Spec, Edge cases).
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    storage.set(
      try JSONEncoder().encode([
        "steps", "exerciseMinutes", "activeEnergy", "walkingRunningDistance", "restingHeartRate",
        "walkingHeartRateAverage", "heartRate", "heartRateVariability", "respiratoryRate", "bloodGlucose",
        "bloodOxygen", "sleep", "weight",
      ]), forKey: AppSettings.Key.healthTypesAskedAbout)
    let enabled = HealthType.enabledTypes(cycleTrackingEnabled: false)

    let observedBefore = HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout)
    #expect(!observedBefore.contains(.restingEnergy))
    #expect(!observedBefore.contains(.flightsClimbed))
    #expect(!observedBefore.contains(.standMinutes))
    #expect(observedBefore.count == 13)

    settings.recordHealthTypesAskedAbout([.restingEnergy, .flightsClimbed, .standMinutes])
    let knownIn042 = enabled.filter {
      ![
        HealthType.cardioFitness, .walkingSpeed, .wristTemperature, .walkingStepLength, .walkingAsymmetry,
        .doubleSupportTime,
      ].contains($0)
    }
    #expect(HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout) == knownIn042)
    #expect(knownIn042.count == 16)
  }

  @Test func aPersisted042AskedSetLeavesTheNewTypesUnobservedUntilRecorded() throws {
    // A 0.4.2 install persisted the sixteen base types; the new ones stay unobserved until the sheet is answered (VO2 Max, Walking Speed and Wrist Temperature Spec, Edge cases).
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    storage.set(
      try JSONEncoder().encode([
        "steps", "exerciseMinutes", "activeEnergy", "walkingRunningDistance", "restingEnergy", "flightsClimbed",
        "standMinutes", "restingHeartRate", "walkingHeartRateAverage", "heartRate", "heartRateVariability",
        "respiratoryRate", "bloodGlucose", "bloodOxygen", "sleep", "weight",
      ]), forKey: AppSettings.Key.healthTypesAskedAbout)
    let enabled = HealthType.enabledTypes(cycleTrackingEnabled: false)

    let observedBefore = HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout)
    #expect(!observedBefore.contains(.cardioFitness))
    #expect(!observedBefore.contains(.walkingSpeed))
    #expect(!observedBefore.contains(.wristTemperature))
    #expect(observedBefore.count == 16)

    settings.recordHealthTypesAskedAbout([.cardioFitness, .walkingSpeed, .wristTemperature])
    let knownIn043 = enabled.filter {
      ![HealthType.walkingStepLength, .walkingAsymmetry, .doubleSupportTime].contains($0)
    }
    #expect(HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout) == knownIn043)
    #expect(knownIn043.count == 19)
  }

  @Test func aPersisted043AskedSetLeavesTheNewTypesUnobservedUntilRecorded() throws {
    // A 0.4.3 install persisted the nineteen base types; the new ones stay unobserved until the sheet is answered (Walking Step Length, Asymmetry and Double Support Spec, Edge cases).
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    storage.set(
      try JSONEncoder().encode([
        "steps", "exerciseMinutes", "activeEnergy", "walkingRunningDistance", "restingEnergy", "flightsClimbed",
        "standMinutes", "walkingSpeed", "restingHeartRate", "walkingHeartRateAverage", "heartRate",
        "heartRateVariability", "cardioFitness", "respiratoryRate", "bloodGlucose", "bloodOxygen", "sleep", "weight",
        "wristTemperature",
      ]), forKey: AppSettings.Key.healthTypesAskedAbout)
    let enabled = HealthType.enabledTypes(cycleTrackingEnabled: false)

    let observedBefore = HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout)
    #expect(!observedBefore.contains(.walkingStepLength))
    #expect(!observedBefore.contains(.walkingAsymmetry))
    #expect(!observedBefore.contains(.doubleSupportTime))
    #expect(observedBefore.count == 19)

    settings.recordHealthTypesAskedAbout([.walkingStepLength, .walkingAsymmetry, .doubleSupportTime])
    let observedAfter = HealthType.observedTypes(enabled: enabled, askedAbout: settings.healthTypesAskedAbout)
    #expect(
      Set(observedAfter).subtracting(observedBefore) == [.walkingStepLength, .walkingAsymmetry, .doubleSupportTime])
    #expect(observedAfter.count == 22)
    #expect(observedAfter == enabled)
  }

  @Test func theFixedPreSettingListNeverGainsWalkingHeartRateAverage() {
    // Existing installs must see the Health sheet before the new type is observed (Walking Heart Rate Average Spec, Edge cases).
    #expect(!AppSettings.typesAskedAboutBeforeThisSetting.contains(.walkingHeartRateAverage))
  }

  @Test func theFixedPreSettingListNeverGainsHeartRate() {
    // Heart rate is a base type asked of everyone (Heart Rate Spec, Edge cases).
    #expect(!AppSettings.typesAskedAboutBeforeThisSetting.contains(.heartRate))
  }

  @Test func theFixedPreSettingListNeverGainsEnergyDistanceOrHRV() {
    // Existing installs must see the Health sheet before these types are observed (Energy, Distance and HRV Spec, Edge cases).
    let asked = AppSettings.typesAskedAboutBeforeThisSetting
    #expect(!asked.contains(.activeEnergy))
    #expect(!asked.contains(.walkingRunningDistance))
    #expect(!asked.contains(.heartRateVariability))
  }

  @Test func theFixedPreSettingListNeverGainsRestingEnergyFlightsOrStand() {
    // Existing installs must see the Health sheet before these types are observed (Resting Energy, Flights and Stand Spec, Edge cases).
    let asked = AppSettings.typesAskedAboutBeforeThisSetting
    #expect(!asked.contains(.restingEnergy))
    #expect(!asked.contains(.flightsClimbed))
    #expect(!asked.contains(.standMinutes))
  }

  @Test func theFixedPreSettingListNeverGainsCardioFitnessWalkingSpeedOrWristTemperature() {
    // Existing installs must see the Health sheet before these types are observed (VO2 Max, Walking Speed and Wrist Temperature Spec, Edge cases).
    let asked = AppSettings.typesAskedAboutBeforeThisSetting
    #expect(!asked.contains(.cardioFitness))
    #expect(!asked.contains(.walkingSpeed))
    #expect(!asked.contains(.wristTemperature))
  }

  @Test func theFixedPreSettingListNeverGainsStepLengthAsymmetryOrDoubleSupport() {
    // Existing installs must see the Health sheet before these types are observed (Walking Step Length, Asymmetry and Double Support Spec, Edge cases).
    let asked = AppSettings.typesAskedAboutBeforeThisSetting
    #expect(!asked.contains(.walkingStepLength))
    #expect(!asked.contains(.walkingAsymmetry))
    #expect(!asked.contains(.doubleSupportTime))
  }

  @Test func concurrentRecordingsOfDifferentTypesAllSurvive() async {
    let settings = AppSettings(storage: InMemoryStorage())

    await withTaskGroup(of: Void.self) { group in
      for type in HealthType.allCases {
        group.addTask { settings.recordHealthTypesAskedAbout([type]) }
      }
    }

    #expect(settings.healthTypesAskedAbout == Set(HealthType.allCases))
  }

  @Test func hasTippedDefaultsToFalseAndPersists() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    #expect(settings.hasTipped == false)

    settings.hasTipped = true
    #expect(AppSettings(storage: storage).hasTipped == true)
  }

  @Test func exportFormatsDefaultsWhenMissingCorruptOrEmpty() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)
    #expect(settings.exportFormats == [.json, .markdown])
    #expect(settings.exportFormatsCovered == [.json, .markdown])

    storage.set(Data("not json".utf8), forKey: AppSettings.Key.exportFormats)
    #expect(settings.exportFormats == [.json, .markdown])

    storage.set(Data("[]".utf8), forKey: AppSettings.Key.exportFormats)
    #expect(settings.exportFormats == [.json, .markdown])
  }

  @Test func unknownFormatValuesAreIgnored() throws {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)

    storage.set(try JSONEncoder().encode(["json", "aFormatFromALaterVersion"]), forKey: AppSettings.Key.exportFormats)
    #expect(settings.exportFormats == [.json])

    storage.set(try JSONEncoder().encode(["aFormatFromALaterVersion"]), forKey: AppSettings.Key.exportFormats)
    #expect(settings.exportFormats == [.json, .markdown])
  }

  @Test func settingNoFormatsIsRefused() {
    let storage = InMemoryStorage()
    let settings = AppSettings(storage: storage)

    #expect(settings.setExportFormats([.markdown]))
    #expect(settings.setExportFormats([]) == false)

    #expect(AppSettings(storage: storage).exportFormats == [.markdown])
  }

  @Test func coveredFormatsRoundTrip() {
    let storage = InMemoryStorage()
    AppSettings(storage: storage).exportFormatsCovered = [.json]

    #expect(AppSettings(storage: storage).exportFormatsCovered == [.json])
  }
}
