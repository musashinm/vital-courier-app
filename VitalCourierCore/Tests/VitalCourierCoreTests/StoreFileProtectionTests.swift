import Foundation
import GRDB
import Synchronization
import Testing
@testable import VitalCourierCore

struct ProtectionFailed: Error {}

/// Records every URL the store protects and can be told to fail.
final class ProtectionProbe: Sendable {
    private let state = Mutex<(visited: [String], failing: Bool)>(([], false))
    func record(_ url: URL) throws {
        let shouldFail = state.withLock { state -> Bool in
            state.visited.append(url.path)
            return state.failing
        }
        if shouldFail { throw ProtectionFailed() }
    }
    func setFailing(_ failing: Bool) { state.withLock { $0.failing = failing } }
    func visitCount(of path: String) -> Int { state.withLock { $0.visited.filter { $0 == path }.count } }
}

@Suite struct StoreFileProtectionTests {
    func makeDirectory(files: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in files { try Data("x".utf8).write(to: directory.appendingPathComponent(name)) }
        return directory
    }

    @Test func theDirectoryAndEveryChildFileAreVisited() throws {
        let directory = try makeDirectory(files: ["local-store.sqlite", "local-store.sqlite-journal", "local-store.sqlite-wal", "local-store.sqlite-shm", "scratch.tmp"])
        defer { try? FileManager.default.removeItem(at: directory) }
        var visited: [String] = []

        try StoreFileProtection.apply(to: directory) { visited.append($0.lastPathComponent) }

        #expect(visited == [directory.lastPathComponent, "local-store.sqlite", "local-store.sqlite-journal", "local-store.sqlite-shm", "local-store.sqlite-wal", "scratch.tmp"])
    }

    @Test func aFailureStopsTheWalkAndPropagates() throws {
        let directory = try makeDirectory(files: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }
        var visitedCount = 0

        #expect(throws: ProtectionFailed.self) {
            try StoreFileProtection.apply(to: directory) { _ in
                visitedCount += 1
                if visitedCount == 2 { throw ProtectionFailed() }
            }
        }
        #expect(visitedCount == 2)
    }

    @Test func protectFilesCoversASidecarCreatedAfterOpening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore.open(directory: directory)
        try Data("x".utf8).write(to: directory.appendingPathComponent("local-store.sqlite-journal"))
        var visited: [String] = []

        try store.protectFiles { visited.append($0.lastPathComponent) }

        #expect(visited.first == directory.lastPathComponent)
        #expect(visited.contains("local-store.sqlite"))
        #expect(visited.contains("local-store.sqlite-journal"))
    }

    @Test func theInMemoryStoreHasNothingToProtect() throws {
        var visitedCount = 0

        try LocalStore.inMemory().protectFiles { _ in visitedCount += 1 }

        #expect(visitedCount == 0)
    }

    func openStore(probe: ProtectionProbe, directory: URL? = nil, pendingFailures: InMemoryStorage = InMemoryStorage()) throws -> (store: LocalStore, directory: URL) {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore.open(directory: directory, pendingFailureStore: pendingFailures) { try probe.record($0) }
        return (store, directory)
    }

    @Test func everyWritePathProtectsTheDirectoryAfterwards() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes: [(name: String, perform: () throws -> Void)] = [
            ("applyChanges", { try store.applyChanges(HealthChanges(added: [makeSample(start: "2026-09-27T12:00:00Z")], newAnchor: Data([1])), for: .steps, fallbackTimeZone: saoPaulo) }),
            ("saveDailyValue", { try store.saveDailyValue(DailyValue(value: 1), type: .steps, day: day("2026-09-27")) }),
            ("markNotFresh", { try store.markNotFresh(type: .steps, day: day("2026-09-27")) }),
            ("clearDirty", { try store.clearDirty(type: .steps, day: day("2026-09-27")) }),
            ("markAllDirty", { try store.markAllDirty(statisticsZone: saoPaulo) }),
            ("setSleepSourcePreference", { try store.setSleepSourcePreference("Apple Watch") }),
            ("appendRun", { try store.appendRun(RunRecord(startedAt: date("2026-09-27T12:00:00Z"), trigger: "appOpen", readOutcome: "read", daysWritten: 0, daysFailed: 0, daysPending: 0, errors: [])) }),
            ("clearLocalCopy", { try store.clearLocalCopy() }),
        ]

        for write in writes {
            let before = probe.visitCount(of: directory.path)
            try write.perform()
            #expect(probe.visitCount(of: directory.path) == before + 1, "\(write.name) did not protect the store afterwards")
        }
    }

    @Test func aProtectionFailureAfterAWriteIsKeptNotThrown() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        probe.setFailing(true)

        try store.setSleepSourcePreference("Apple Watch")

        #expect(try store.sleepSourcePreference() == "Apple Watch")
        // Reading the queue does not clear it: only a saved history row does.
        #expect(store.pendingProtectionFailures() == ["ProtectionFailed()"])
        #expect(store.pendingProtectionFailures() == ["ProtectionFailed()"])
    }

    @Test func pendingProtectionFailuresBecomeOneRunHistoryRow() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        probe.setFailing(true)
        try store.setSleepSourcePreference("Apple Watch")
        probe.setFailing(false)

        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:00:00Z"))
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:01:00Z"))

        let runs = try store.recentRuns(limit: 10)
        #expect(runs.count == 1)
        #expect(runs[0].trigger == RunRecord.appEventTrigger)
        #expect(runs[0].errors == ["file protection: ProtectionFailed()"])
        #expect(store.pendingProtectionFailures().isEmpty)
    }

    @Test func aFailureWhileWritingTheRecordStaysPendingUntilTheNextCall() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        probe.setFailing(true)
        try store.setSleepSourcePreference("Apple Watch")

        // Writing the row fails protection again: the first failure is saved, the new one waits.
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:00:00Z"))

        #expect(try store.recentRuns(limit: 10).count == 1)
        #expect(store.pendingProtectionFailures() == ["ProtectionFailed()"])

        probe.setFailing(false)
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:01:00Z"))

        #expect(try store.recentRuns(limit: 10).count == 2)
        #expect(store.pendingProtectionFailures().isEmpty)
    }

    @Test func aProtectionFailureWhileWritingTheHistoryRowSurvivesARelaunch() throws {
        let probe = ProtectionProbe()
        let pendingFailures = InMemoryStorage()
        var (store, directory) = try openStore(probe: probe, pendingFailures: pendingFailures)
        defer { try? FileManager.default.removeItem(at: directory) }
        probe.setFailing(true)
        try store.setSleepSourcePreference("Apple Watch")
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:00:00Z"))
        // The app exits here, with the failure from saving the row not yet in History.
        #expect(store.pendingProtectionFailures() == ["ProtectionFailed()"])

        probe.setFailing(false)
        store = try openStore(probe: probe, directory: directory, pendingFailures: pendingFailures).store
        #expect(store.pendingProtectionFailures() == ["ProtectionFailed()"])
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:05:00Z"))

        let runs = try store.recentRuns(limit: 10)
        #expect(runs.count == 2)
        #expect(runs[0].trigger == RunRecord.appEventTrigger)
        #expect(runs[0].errors == ["file protection: ProtectionFailed()"])
        #expect(store.pendingProtectionFailures().isEmpty)
    }

    @Test func anAppEventRowIsNeverTheLatestRun() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appOpenRun = { (start: String) in
            RunRecord(startedAt: date(start), trigger: Trigger.appOpen.rawValue, readOutcome: ReadOutcome.read.rawValue, daysWritten: 1, daysFailed: 0, daysPending: 0, errors: [])
        }
        #expect(try store.statusSnapshot().latestRun == nil)
        try store.appendRun(appOpenRun("2026-10-03T10:00:00Z"))
        try store.recordAppEvent(errors: ["file protection: ProtectionFailed()"], at: date("2026-10-03T11:00:00Z"))

        // The App event row is the newest row, but it checked nothing: Home's latest run is still the app-open run.
        let snapshot = try store.statusSnapshot()
        #expect(snapshot.latestRun?.trigger == Trigger.appOpen.rawValue)
        #expect(snapshot.latestAppEvent?.errors == ["file protection: ProtectionFailed()"])
        #expect(try store.recentRuns(limit: 10).count == 2)

        // A later real run ends the App event's turn as the newest row.
        try store.appendRun(appOpenRun("2026-10-03T12:00:00Z"))
        #expect(try store.statusSnapshot().latestAppEvent == nil)
    }

    struct TaggedFailure: Error { let tag: String }

    /// Two drains overlap, and a new failure arrives between them. Drain A is held inside its history-row write; drain B runs (or, with the drain lock, waits); failure two is queued; then A resumes. Every failure must end up in exactly one row or still be queued.
    @Test func aFailureQueuedDuringAnotherDrainIsNeitherLostNorSavedTwice() throws {
        struct Control { var nextTag: String?; var blockNextCall = false }
        let control = Mutex(Control())
        let enteredBlockedCall = DispatchSemaphore(value: 0)
        let releaseBlockedCall = DispatchSemaphore(value: 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore.open(directory: directory, pendingFailureStore: InMemoryStorage()) { _ in
            let (tag, shouldBlock) = control.withLock { state -> (String?, Bool) in
                defer { state.nextTag = nil; state.blockNextCall = false }
                return (state.nextTag, state.blockNextCall)
            }
            if shouldBlock {
                enteredBlockedCall.signal()
                releaseBlockedCall.wait()
            }
            if let tag { throw TaggedFailure(tag: tag) }
        }
        control.withLock { $0.nextTag = "one" }
        try store.setSleepSourcePreference("Apple Watch")
        #expect(store.pendingProtectionFailures().count == 1)

        let drainsFinished = DispatchGroup()
        control.withLock { $0.blockNextCall = true }
        DispatchQueue.global().async(group: drainsFinished) {
            try? store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:00:00Z"))
        }
        // Drain A has snapshotted failure one and is inside its row write.
        enteredBlockedCall.wait()
        let secondDrainFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async(group: drainsFinished) {
            try? store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:01:00Z"))
            secondDrainFinished.signal()
        }
        // Without the drain lock this drain completes while A is held; with it, it waits for A. This bounded wait only lets an unserialized drain show itself: the assertions below hold for any ordering when the lock exists.
        _ = secondDrainFinished.wait(timeout: .now() + 1)
        control.withLock { $0.nextTag = "two" }
        try store.setSleepSourcePreference("Apple Watch, again")
        releaseBlockedCall.signal()
        drainsFinished.wait()
        try store.recordProtectionFailuresInHistory(at: date("2026-10-03T12:02:00Z"))

        let savedErrors = try store.recentRuns(limit: 10).flatMap(\.errors)
        let everyFailure = savedErrors + store.pendingProtectionFailures().map { RunRecord.fileProtectionErrorPrefix + $0 }
        #expect(everyFailure.filter { $0.contains("one") }.count == 1)
        #expect(everyFailure.filter { $0.contains("two") }.count == 1)
    }

    @Test func aRealWriteTransactionShowsTheJournalAndRollsBack() throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("local-store.sqlite-journal").path))

        let namesDuringWrite = try store.withWriteTransactionOpen {
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        }

        print("files during write:", namesDuringWrite)
        #expect(namesDuringWrite.contains("local-store.sqlite-journal"))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("local-store.sqlite-journal").path))
        let userVersion = try store.dbQueue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
        #expect(userVersion == 0)
    }

    @Test func anUnreadablePendingQueueIsReportedNotDropped() throws {
        let probe = ProtectionProbe()
        let pendingFailures = InMemoryStorage()
        pendingFailures.set(Data("not json".utf8), forKey: LocalStore.pendingProtectionFailuresKey)
        let (store, directory) = try openStore(probe: probe, pendingFailures: pendingFailures)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.pendingProtectionFailures().count == 1)
        #expect(store.pendingProtectionFailures()[0].hasPrefix("unreadable pending failure queue: "))
    }

    @Test func aRunRecordsAProtectionFailureInItsOwnHistoryRow() async throws {
        let probe = ProtectionProbe()
        let (store, directory) = try openStore(probe: probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedNow = date("2026-10-03T12:00:00Z")
        let runner = ExportRunner(store: store, health: FakeHealthSource(), destination: { nil }, now: { fixedNow }, timeZone: { saoPaulo })
        probe.setFailing(true)

        // Rebuild all writes to the store (markAllDirty) before the run record is saved.
        let outcome = await runner.run(trigger: .rebuildAll, options: .forTrigger(.rebuildAll)) {}

        #expect(outcome.errors.contains("file protection: ProtectionFailed()"))
        let run = try #require(try store.recentRuns(limit: 1).first)
        #expect(run.errors.contains("file protection: ProtectionFailed()"))
        // The run's row holds the failure, so only the one from writing that row itself can still be pending.
        #expect(store.pendingProtectionFailures().count <= 1)
    }
}
