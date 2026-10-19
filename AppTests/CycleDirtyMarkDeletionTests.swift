import Dispatch
import Foundation
import Synchronization
import Testing
import VitalCourierCore

@testable import VitalCourier

/// Stops the first read of the Cycle tracking switch after it has fetched its value, and records whether the marks were already deleted when the switch was written.
/// It blocks with semaphores, so only dedicated threads may call it, never a Swift concurrency task.
private final class GatedSwitchStorage: KeyValueStorage {
  private let values = InMemoryStorage()
  private let readHasFetchedValue = DispatchSemaphore(value: 0)
  private let allowReadToReturn = DispatchSemaphore(value: 0)
  private let switchWasWritten = DispatchSemaphore(value: 0)
  private let marksAreDeleted: @Sendable () throws -> Bool
  private let marksWereDeletedAtSwitchWrite = Mutex<Result<Bool, Error>?>(nil)

  init(marksAreDeleted: @escaping @Sendable () throws -> Bool) {
    self.marksAreDeleted = marksAreDeleted
  }

  func data(forKey key: String) -> Data? {
    let value = values.data(forKey: key)
    readHasFetchedValue.signal()
    allowReadToReturn.wait()
    return value
  }

  func set(_ data: Data?, forKey key: String) {
    let deleted = Result { try marksAreDeleted() }
    marksWereDeletedAtSwitchWrite.withLock { $0 = deleted }
    values.set(data, forKey: key)
    switchWasWritten.signal()
  }

  func waitUntilReadHasFetchedValue() { readHasFetchedValue.wait() }
  func letReadReturn() { allowReadToReturn.signal() }
  /// True when the switch was written within the timeout.
  func waitForSwitchWrite(timeout: DispatchTimeInterval) -> Bool {
    switchWasWritten.wait(timeout: .now() + timeout) == .success
  }
  var marksWereDeletedWhenSwitchWasWritten: Result<Bool, Error>? { marksWereDeletedAtSwitchWrite.withLock { $0 } }
}

/// Runs a blocking body on its own thread and resumes the awaiting test when it ends, so no Swift concurrency thread ever blocks.
private func runOnDedicatedThread<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    let thread = Thread { continuation.resume(with: Result { try body() }) }
    thread.start()
  }
}

@Suite struct CycleDirtyMarkDeletionTests {
  private let day = DayKey(year: 2026, month: 10, day: 12)

  private func storeWithPendingCycleMark() throws -> LocalStore {
    let store = try LocalStore.inMemory()
    try store.saveCycleDay(.flow("light", periodStart: false), day: day)
    #expect(try store.dirtyEntries().map(\.type) == [.menstrualFlow])
    return store
  }

  @Test func theMarksAreDeletedWhileTrackingIsStillOff() throws {
    let store = try storeWithPendingCycleMark()
    let settings = AppSettings(storage: InMemoryStorage())

    try CycleTrackingTransition().deleteMarksIfStillOff(in: store, settings: settings)

    #expect(try store.dirtyEntries().isEmpty)
  }

  @Test func theMarksSurviveWhenTrackingIsBackOnBeforeTheDeletionRuns() throws {
    let store = try storeWithPendingCycleMark()
    let settings = AppSettings(storage: InMemoryStorage())
    let transition = CycleTrackingTransition()

    // Off, then on again while the deletion waited for the coordinator: the switch reads true by the time it runs.
    transition.setEnabled(true, in: settings)
    try transition.deleteMarksIfStillOff(in: store, settings: settings)

    #expect(try store.dirtyEntries().map(\.type) == [.menstrualFlow])
  }

  @Test func aSwitchChangeWaitsForARunningDeletionToFinish() async throws {
    let store = try storeWithPendingCycleMark()
    let storage = GatedSwitchStorage { try store.dirtyEntries().isEmpty }
    let settings = AppSettings(storage: storage)
    let transition = CycleTrackingTransition()

    let switchWrittenWhileDeletionWasHeld = try await runOnDedicatedThread {
      // The deletion has read "off" and is held there. A setter issued now must wait for the lock instead of writing between the read and the delete.
      let deletionFinished = DispatchSemaphore(value: 0)
      let deletionError = Mutex<Error?>(nil)
      Thread {
        do { try transition.deleteMarksIfStillOff(in: store, settings: settings) } catch {
          deletionError.withLock { $0 = error }
        }
        deletionFinished.signal()
      }.start()
      storage.waitUntilReadHasFetchedValue()

      let setterFinished = DispatchSemaphore(value: 0)
      Thread {
        transition.setEnabled(true, in: settings)
        setterFinished.signal()
      }.start()

      // Without the lock the setter writes at once, so a bounded wait while the gate is closed tells the two cases apart.
      let wroteWhileHeld = storage.waitForSwitchWrite(timeout: .milliseconds(500))
      storage.letReadReturn()
      deletionFinished.wait()
      setterFinished.wait()
      if let error = deletionError.withLock({ $0 }) { throw error }
      return wroteWhileHeld
    }

    #expect(!switchWrittenWhileDeletionWasHeld)
    #expect(try storage.marksWereDeletedWhenSwitchWasWritten?.get() == true)
    #expect(try store.dirtyEntries().isEmpty)
  }
}
