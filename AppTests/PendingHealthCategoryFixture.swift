// The mapped pending HealthKit identifiers (design Home Categories, section 6) as raw strings: they are not `HealthType` cases until they ship.
@testable import VitalCourier

let pendingIdentifiersByCategory: [HealthCategory: [String]] = [
  .activity: [
    "appleMoveTime", "physicalEffort", "workoutEffortScore",
    "estimatedWorkoutEffortScore", "runningSpeed",
    "runningPower", "distanceCycling", "cyclingSpeed", "cyclingPower", "cyclingCadence",
    "cyclingFunctionalThresholdPower", "distanceSwimming", "swimmingStrokeCount", "underwaterDepth",
    "distanceWheelchair", "pushCount", "distanceDownhillSnowSports", "distanceCrossCountrySkiing",
    "crossCountrySkiingSpeed", "distanceRowing", "rowingSpeed", "distancePaddleSports", "paddleSportsSpeed",
    "distanceSkatingSports", "appleStandHour", "workout",
  ],
  .bodyMeasurements: [
    "height", "bodyMassIndex", "leanBodyMass", "bodyFatPercentage", "waistCircumference", "hipCircumference",
    "electrodermalActivity",
  ],
  .cycleTracking: [
    "basalBodyTemperature", "infrequentMenstrualCycles", "irregularMenstrualCycles",
    "persistentIntermenstrualBleeding", "prolongedMenstrualPeriods", "cervicalMucusQuality", "ovulationTestResult",
    "progesteroneTestResult", "pregnancyTestResult", "sexualActivity", "contraceptive", "pregnancy", "lactation",
    "menopausalState", "bleedingAfterMenopause",
  ],
  .hearing: [
    "environmentalAudioExposure", "environmentalSoundReduction", "headphoneAudioExposure",
    "environmentalAudioExposureEvent", "headphoneAudioExposureEvent", "audiogram",
  ],
  .heart: [
    "heartRateVariabilityRMSSD", "heartRateRecoveryOneMinute", "atrialFibrillationBurden",
    "peripheralPerfusionIndex", "bloodPressureSystolic", "bloodPressureDiastolic", "highHeartRateEvent",
    "lowHeartRateEvent", "irregularHeartRhythmEvent", "hypertensionEvent", "lowCardioFitnessEvent",
    "electrocardiogram", "heartbeatSeries",
  ],
  .mentalWellbeing: [
    "mindfulSession", "stateOfMind",
  ],
  .mobility: [
    "appleWalkingSteadiness", "sixMinuteWalkTestDistance", "stairAscentSpeed", "stairDescentSpeed",
    "runningStrideLength", "runningGroundContactTime", "runningVerticalOscillation", "appleWalkingSteadinessEvent",
  ],
  .nutrition: [
    "dietaryEnergyConsumed", "dietaryProtein", "dietaryCarbohydrates", "dietarySugar", "dietaryFiber",
    "dietaryFatTotal", "dietaryFatSaturated", "dietaryFatMonounsaturated", "dietaryFatPolyunsaturated",
    "dietaryCholesterol", "dietaryWater", "dietaryCaffeine", "dietaryVitaminA", "dietaryVitaminB6",
    "dietaryVitaminB12", "dietaryVitaminC", "dietaryVitaminD", "dietaryVitaminE", "dietaryVitaminK", "dietaryThiamin",
    "dietaryRiboflavin", "dietaryNiacin", "dietaryPantothenicAcid", "dietaryFolate", "dietaryBiotin",
    "dietaryCalcium", "dietaryChloride", "dietaryChromium", "dietaryCopper", "dietaryIodine", "dietaryIron",
    "dietaryMagnesium", "dietaryManganese", "dietaryMolybdenum", "dietaryPhosphorus", "dietaryPotassium",
    "dietarySelenium", "dietarySodium", "dietaryZinc",
  ],
  .respiratory: [
    "appleSleepingBreathingDisturbances", "forcedExpiratoryVolume1", "forcedVitalCapacity", "peakExpiratoryFlowRate",
    "inhalerUsage",
  ],
  .sleep: [],
  .symptoms: [
    "abdominalCramps", "acne", "appetiteChanges", "bladderIncontinence", "bloating", "breastPain",
    "chestTightnessOrPain", "chills", "constipation", "coughing", "diarrhea", "dizziness", "drySkin", "fainting",
    "fatigue", "fever", "generalizedBodyAche", "hairLoss", "headache", "heartburn", "hotFlashes", "lossOfSmell",
    "lossOfTaste", "lowerBackPain", "memoryLapse", "moodChanges", "nausea", "nightSweats", "pelvicPain",
    "rapidPoundingOrFlutteringHeartbeat", "runnyNose", "shortnessOfBreath", "sinusCongestion", "skippedHeartbeat",
    "sleepChanges", "soreThroat", "vaginalDryness", "vomiting", "wheezing",
  ],
  .vitals: ["bodyTemperature"],
  .otherData: [
    "bloodAlcoholContent", "numberOfAlcoholicBeverages", "uvExposure", "timeInDaylight", "waterTemperature",
    "insulinDelivery", "numberOfTimesFallen", "toothbrushingEvent", "handwashingEvent",
  ],
]
