import Synchronization
import VitalCourierCore

/// Serializes the Cycle tracking switch with the deletion of its dirty marks. Without it, the deletion could read "off", the user's off-to-on change could land, and the deletion would then drop marks of a run that already committed its anchors, losing that cycle data from the export.
/// The lock is held only across a synchronous settings write, or a synchronous settings read plus one store write. Never `await` inside it.
final class CycleTrackingTransition: Sendable {
    private let lock = Mutex(())

    func setEnabled(_ isEnabled: Bool, in settings: AppSettings) {
        lock.withLock { _ in settings.cycleTrackingEnabled = isEnabled }
    }

    /// Deletes the cycle dirty marks unless tracking is on again. Call it inside the coordinator's exclusive section: the marks of a run that turned tracking back on are the only record of its cycle data, because the run's anchors are already committed.
    func deleteMarksIfStillOff(in store: LocalStore, settings: AppSettings) throws {
        try lock.withLock { _ in
            guard !settings.cycleTrackingEnabled else { return }
            try store.deleteDirtyMarks(types: HealthType.cycleTypes)
        }
    }
}
