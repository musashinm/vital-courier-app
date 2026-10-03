import Dispatch
import HealthKit
import VitalCourierCore
import VitalCourierHealthKit

/// HealthKit observer queries with background delivery for the four types (spec, Triggers: Observer wake).
enum ObserverRegistration {
    /// How long the HealthKit callback waits for the read to commit before it acknowledges anyway. A guess, to be tuned on a device (On-device checklist 12); no documentation gives a number. The coordinator already acknowledges at once behind Rebuild all (Task 1), so this only bounds a long first read or a hung one.
    static let acknowledgementBudgetSeconds = 30
    static let acknowledgementTimeout: DispatchTimeInterval = .seconds(acknowledgementBudgetSeconds)

    /// Call at every launch once setup is done, and when setup completes. Queries die with the process; iOS relaunches the app in the background for types with background delivery on, and the queries must be running again by the end of `didFinishLaunching`.
    static func start(environment: AppEnvironment) {
        guard environment.markObserversStarted() else { return }
        let healthStore = environment.health.healthStore
        for type in HealthType.allCases {
            let sampleType = HealthKitMapping.sampleType(for: type)
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
                // `completionHandler` is not Sendable, and neither `@Sendable` nor `sending` accepts it (Facts to verify 21), so it never leaves this closure: `AcknowledgementGate.wait` blocks this thread until the read commits, the run fails or the budget runs out, and the handler is called here, once, at the single call site below.
                //
                // Tradeoff, not a free wait. HealthKit runs the update handlers on one anonymous background queue (https://developer.apple.com/documentation/healthkit/executing-observer-queries), and a thread blocked on a `DispatchSemaphore` is held until it is signalled or times out (https://developer.apple.com/documentation/dispatch/dispatchsemaphore), so a long wait can delay the next handler, and a timeout acknowledges before the read has committed. The wait is kept because the app stays awake in the background until the handler is called, which is the time it needs to commit the read; the app is relying on that behaviour, and no documentation promises a 30 second allowance (Facts to verify 25). A timeout is saved as a run-history row below, and the run keeps going.
                if let error {
                    environment.recordSetupError("observer \(type.rawValue): \(error)")
                    completionHandler()
                    return
                }
                let outcome = AcknowledgementGate.wait(
                    timeout: acknowledgementTimeout,
                    onFailure: { environment.recordSetupError("observer \(type.rawValue) run: \($0)") },
                    work: { signalReadCommitted in
                        _ = try await environment.request(.observerWake, onReadCommitted: signalReadCommitted)
                    }
                )
                if outcome == .timedOut {
                    environment.recordObserverAcknowledgementTimeout(type: type)
                }
                completionHandler()
            }
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { succeeded, error in
                if !succeeded {
                    environment.recordSetupError("background delivery \(type.rawValue): \(error.map { String(describing: $0) } ?? "not enabled")")
                }
            }
        }
    }
}
