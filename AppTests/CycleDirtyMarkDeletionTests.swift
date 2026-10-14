import Dispatch
import Foundation
import Synchronization
import Testing
@testable import VitalCourier
import VitalCourierCore

/// Stops the first read of the Cycle tracking switch after it has fetched its value, and records whether the marks were already deleted when the switch was written.
private final class GatedSwitchStorage: KeyValueStorage {
    private let values = InMemoryStorage()
    private let readHasFetchedValue = DispatchSemaphore(value: 0)
    private let allowReadToReturn = DispatchSemaphore(value: 0)
    private let marksAreDeleted: @Sendable () -> Bool
    private let marksWereDeletedAtSwitchWrite = Mutex<Bool?>(nil)

    init(marksAreDeleted: @escaping @Sendable () -> Bool) {
        self.marksAreDeleted = marksAreDeleted
    }

    func data(forKey key: String) -> Data? {
        let value = values.data(forKey: key)
        readHasFetchedValue.signal()
        allowReadToReturn.wait()
        return value
    }

    func set(_ data: Data?, forKey key: String) {
        let deleted = marksAreDeleted()
        marksWereDeletedAtSwitchWrite.withLock { $0 = deleted }
        values.set(data, forKey: key)
    }

    func waitUntilReadHasFetchedValue() { readHasFetchedValue.wait() }
    func letReadReturn() { allowReadToReturn.signal() }
    var marksWereDeletedWhenSwitchWasWritten: Bool? { marksWereDeletedAtSwitchWrite.withLock { $0 } }
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
        let storage = GatedSwitchStorage { (try? store.dirtyEntries().isEmpty) ?? false }
        let settings = AppSettings(storage: storage)
        let transition = CycleTrackingTransition()

        // The deletion has read "off" and is held there. A setter issued now must wait for the lock instead of writing between the read and the delete.
        let deletion = Task.detached { try transition.deleteMarksIfStillOff(in: store, settings: settings) }
        storage.waitUntilReadHasFetchedValue()
        let setter = Task.detached { transition.setEnabled(true, in: settings) }
        storage.letReadReturn()
        try await deletion.value
        await setter.value

        #expect(storage.marksWereDeletedWhenSwitchWasWritten == true)
        #expect(try store.dirtyEntries().isEmpty)
    }
}
