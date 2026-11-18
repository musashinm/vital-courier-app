import Foundation
import VitalCourierCore

/// The Apple Health category a type is presented under (design Home Categories, sections 6 and 7). Declaration order is Home's order.
enum HealthCategory: CaseIterable, Hashable, Sendable {
  case activity, bodyMeasurements, cycleTracking, hearing, heart, mentalWellbeing, mobility, nutrition,
    respiratory, sleep, symptoms, vitals, otherData

  // swiftlint:disable:next cyclomatic_complexity - one case per Apple Health category
  func name(in localization: AppLocalization = .system) -> String {
    switch self {
    case .activity: localization.string("Activity")
    case .bodyMeasurements: localization.string("Body Measurements")
    case .cycleTracking: localization.string("Cycle Tracking")
    case .hearing: localization.string("Hearing")
    case .heart: localization.string("Heart")
    case .mentalWellbeing: localization.string("Mental Wellbeing")
    case .mobility: localization.string("Mobility")
    case .nutrition: localization.string("Nutrition")
    case .respiratory: localization.string("Respiratory")
    case .sleep: localization.string("Sleep")
    case .symptoms: localization.string("Symptoms")
    case .vitals: localization.string("Vitals")
    case .otherData: localization.string("Other Data")
    }
  }

  var symbolName: String {
    switch self {
    case .activity: "figure.walk"
    case .bodyMeasurements: "scalemass.fill"
    case .cycleTracking: "drop.fill"
    case .hearing: "ear"
    case .heart: "heart.fill"
    case .mentalWellbeing: "brain.head.profile"
    case .mobility: "figure.walk.motion"
    case .nutrition: "fork.knife"
    case .respiratory: "lungs.fill"
    case .sleep: "bed.double.fill"
    case .symptoms: "cross.case.fill"
    case .vitals: "waveform.path.ecg.rectangle.fill"
    case .otherData: "ellipsis.circle.fill"
    }
  }
}

extension HealthType {
  /// The category Apple Health's Browse tab presents the type in. Exhaustive, so a new type has to be placed to compile.
  var category: HealthCategory {
    switch self {
    case .steps, .exerciseMinutes, .activeEnergy, .walkingRunningDistance: .activity
    case .weight: .bodyMeasurements
    case .menstrualFlow, .spotting: .cycleTracking
    case .restingHeartRate, .walkingHeartRateAverage, .heartRate, .heartRateVariability: .heart
    case .respiratoryRate, .bloodOxygen: .respiratory
    case .sleep: .sleep
    case .bloodGlucose: .vitals
    }
  }
}
