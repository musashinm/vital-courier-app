import Foundation
import VitalCourierCore

/// Home's value line for the two cycle rows (Cycle Tracking Spec, UI): the last logged day. No "silent for a week" warning, since cycle data is irregular by nature.
enum CycleRowText {
    static func valueText(for type: HealthType, snapshot: StoreStatusSnapshot?, formatter: StatusDateFormatter, today: DayKey) -> String {
        let localization = formatter.localization
        switch type {
        case .menstrualFlow:
            guard let day = snapshot?.latestFlowDay else { return localization.string("No entries yet") }
            return flowName(snapshot?.latestFlow, in: localization) + " · " + formatter.day(day, today: today)
        case .spotting:
            guard let day = snapshot?.latestSpottingDay else { return localization.string("No entries yet") }
            return formatter.capitalizedFirst(formatter.day(day, today: today))
        case .steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .heartRate, .respiratoryRate, .bloodGlucose, .bloodOxygen, .sleep, .weight:
            return ""
        }
    }

    /// A value a later iOS adds is shown as stored.
    static func flowName(_ flow: String?, in localization: AppLocalization) -> String {
        guard let flow else { return "" }
        switch flow {
        case "light": return localization.string("Light")
        case "medium": return localization.string("Medium")
        case "heavy": return localization.string("Heavy")
        case "unspecified": return localization.string("Unspecified")
        case "none": return localization.string("No flow")
        default: return flow
        }
    }
}
