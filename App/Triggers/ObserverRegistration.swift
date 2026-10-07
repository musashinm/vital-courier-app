import HealthKit
import UIKit
import VitalCourierCore
import VitalCourierHealthKit

/// One HealthKit observer query for the four types, with background delivery (spec, Triggers: Observer wake; Observer Acknowledgement Spec).
enum ObserverRegistration {
    /// Call at every launch once setup is done, and when setup completes. Queries die with the process; iOS relaunches the app in the background for types with background delivery on, and the query must be running again by the end of `didFinishLaunching`. Main actor because it reads `UIApplication.shared`.
    @MainActor
    static func start(environment: AppEnvironment) {
        guard environment.markObserversStarted() else { return }
        let application = UIApplication.shared
        let healthStore = environment.health.healthStore
        let descriptors = HealthType.allCases.map { HKQueryDescriptor(sampleType: HealthKitMapping.sampleType(for: $0), predicate: nil) }
        let query = HKObserverQuery(queryDescriptors: descriptors) { _, _, completionHandler, error in
            // Nothing here may block: HealthKit runs this handler on its serial store-client queue, and delivers the run's own query results on that same queue (logged on a device on 2026-10-04). The read is started under background time and HealthKit is acknowledged at once; a run cut short resumes from its last committed anchor on the next trigger. Setup errors go through a Task because recording one can write the store.
            if let error {
                Task { environment.recordSetupError("observer: \(error)") }
                completionHandler()
                return
            }
            ObserverWake.start(
                beginBackgroundTime: { onExpire in
                    let identifier = application.beginBackgroundTask(withName: "Observer wake") { onExpire() }
                    return identifier == .invalid ? nil : identifier.rawValue
                },
                endBackgroundTime: { application.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) },
                onFailure: { environment.recordSetupError("observer run: \($0)") },
                onCutShort: { BackgroundRefresh.submitNextRequest(environment: environment) },
                run: { _ = try await environment.request(.observerWake) }
            )
            completionHandler()
        }
        healthStore.execute(query)
        for type in HealthType.allCases {
            healthStore.enableBackgroundDelivery(for: HealthKitMapping.sampleType(for: type), frequency: .immediate) { succeeded, error in
                if !succeeded {
                    environment.recordSetupError("background delivery \(type.rawValue): \(error.map { String(describing: $0) } ?? "not enabled")")
                }
            }
        }
    }
}
