import Testing
@testable import VitalCourier
import VitalCourierCore

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

        try AppEnvironment.deleteCycleDirtyMarks(in: store, unlessTrackingIsEnabled: { false })

        #expect(try store.dirtyEntries().isEmpty)
    }

    @Test func theMarksSurviveWhenTrackingIsBackOnBeforeTheDeletionRuns() throws {
        let store = try storeWithPendingCycleMark()

        // Off, then on again while the deletion waited for the coordinator: the switch reads true by the time it runs.
        try AppEnvironment.deleteCycleDirtyMarks(in: store, unlessTrackingIsEnabled: { true })

        #expect(try store.dirtyEntries().map(\.type) == [.menstrualFlow])
    }
}
