import HealthKit
import UIKit
import VitalCourierCore
import VitalCourierHealthKit

/// One HealthKit observer query for the enabled types Health has been asked about, with background delivery (spec, Triggers: Observer wake; Observer Acknowledgement Spec; Cycle Tracking Spec, Observer lifecycle). Main actor because it reads `UIApplication.shared` and keeps the running query.
@MainActor
enum ObserverRegistration {
  /// The running query and the types it was built with; nil until `start`.
  private static var running: (query: HKObserverQuery, types: [HealthType])?

  /// Call at every launch once setup is done, and when setup completes. Queries die with the process; iOS relaunches the app in the background for types with background delivery on, and the query must be running again by the end of `didFinishLaunching`.
  static func start(environment: AppEnvironment) {
    guard environment.markObserversStarted() else { return }
    let types = typesToObserve(settings: environment.settings)
    execute(types: types, environment: environment)
    setBackgroundDelivery(enable: types, disable: [], environment: environment)
  }

  /// Cycle tracking changed or a type was just asked about: rebuild the query for the observed types and switch background delivery for the types that changed. Before `start` it does nothing, since `start` reads the switch itself.
  static func update(environment: AppEnvironment) {
    guard let current = running else { return }
    let types = typesToObserve(settings: environment.settings)
    guard types != current.types else { return }
    environment.health.healthStore.stop(current.query)
    execute(types: types, environment: environment)
    let changes = deliveryChanges(from: current.types, to: types)
    setBackgroundDelivery(enable: changes.enable, disable: changes.disable, environment: environment)
  }

  /// The enabled types Health has been asked about. A type not asked yet would fail the whole observer query with "authorization not determined" (Exercise Minutes Spec, Launch observer).
  static func typesToObserve(settings: AppSettings) -> [HealthType] {
    HealthType.observedTypes(
      enabled: HealthType.enabledTypes(cycleTrackingEnabled: settings.cycleTrackingEnabled),
      askedAbout: settings.healthTypesAskedAbout)
  }

  static func descriptors(for types: [HealthType]) -> [HKQueryDescriptor] {
    types.map { HKQueryDescriptor(sampleType: HealthKitMapping.sampleType(for: $0), predicate: nil) }
  }

  static func deliveryChanges(from oldTypes: [HealthType], to newTypes: [HealthType]) -> (
    enable: [HealthType], disable: [HealthType]
  ) {
    (newTypes.filter { !oldTypes.contains($0) }, oldTypes.filter { !newTypes.contains($0) })
  }

  private static func execute(types: [HealthType], environment: AppEnvironment) {
    let application = UIApplication.shared
    let query = HKObserverQuery(queryDescriptors: descriptors(for: types)) { _, _, completionHandler, error in
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
    environment.health.healthStore.execute(query)
    running = (query, types)
  }

  /// Heart rate arrives every few minutes from the Watch and each wake rewrites its month file, so it wakes the app at most hourly (Heart Rate Spec, Background delivery).
  static func backgroundDeliveryFrequency(for type: HealthType) -> HKUpdateFrequency {
    type == .heartRate ? .hourly : .immediate
  }

  private static func setBackgroundDelivery(
    enable typesToEnable: [HealthType], disable typesToDisable: [HealthType], environment: AppEnvironment
  ) {
    let healthStore = environment.health.healthStore
    for type in typesToEnable {
      healthStore.enableBackgroundDelivery(
        for: HealthKitMapping.sampleType(for: type), frequency: backgroundDeliveryFrequency(for: type)
      ) { succeeded, error in
        if !succeeded {
          environment.recordSetupError(
            "background delivery \(type.rawValue): \(error.map { String(describing: $0) } ?? "not enabled")")
        }
      }
    }
    for type in typesToDisable {
      healthStore.disableBackgroundDelivery(for: HealthKitMapping.sampleType(for: type)) { succeeded, error in
        if !succeeded {
          environment.recordSetupError(
            "disable background delivery \(type.rawValue): \(error.map { String(describing: $0) } ?? "not disabled")")
        }
      }
    }
  }
}
