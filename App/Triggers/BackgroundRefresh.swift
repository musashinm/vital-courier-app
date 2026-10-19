import BackgroundTasks
import Foundation

/// `BGAppRefreshTask`: the retry path (spec, Triggers). iOS picks the real time; there is no schedule.
enum BackgroundRefresh {
  static let taskIdentifier = "app.vitalcourier.VitalCourier.refresh"
  static let earliestDelay: TimeInterval = 60 * 60

  /// Must run before `didFinishLaunching` returns.
  @MainActor
  static func register(environment: AppEnvironment) {
    // The task object is not Sendable, so it stays on the main actor: the handler runs on the main queue.
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
      handle(task, environment: environment)
    }
    if !registered {
      environment.recordSetupError("background refresh: registration failed for \(taskIdentifier)")
    }
  }

  static func submitNextRequest(environment: AppEnvironment) {
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: earliestDelay)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      environment.recordSetupError("background refresh submit: \(error)")
    }
  }

  /// Submits the next request first, then runs. Expiry cancels the run: a queued request leaves the coordinator's queue, a running one stops after the current file (spec, Error handling).
  @MainActor
  private static func handle(_ scheduledTask: BGTask, environment: AppEnvironment) {
    guard let task = scheduledTask as? BGAppRefreshTask else {
      scheduledTask.setTaskCompleted(success: false)
      return
    }
    submitNextRequest(environment: environment)
    let run = Task {
      do {
        _ = try await environment.request(.backgroundRefresh)
        task.setTaskCompleted(success: !Task.isCancelled)
      } catch {
        // A cancelled run is the expiry path; any other error is kept for the setup errors list, never dropped.
        if !(error is CancellationError) {
          environment.recordSetupError("background refresh run: \(error)")
        }
        task.setTaskCompleted(success: false)
      }
    }
    task.expirationHandler = { run.cancel() }
  }
}
