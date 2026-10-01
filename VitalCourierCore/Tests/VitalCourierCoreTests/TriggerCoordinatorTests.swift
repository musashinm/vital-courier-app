import Foundation
import Synchronization
import Testing
@testable import VitalCourierCore

/// Polls until `condition` holds, for at most two seconds, instead of spinning on `Task.yield()`.
func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
    for _ in 0..<2_000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("condition not met within 2 seconds")
    throw CancellationError()
}

/// Fake runner whose runs (numbered from 1) can be held before or after they call `onReadCommitted`.
actor GatedRunner: ExportRunning {
    private(set) var calls: [(trigger: Trigger, options: RunOptions)] = []
    private(set) var cancelledAtStart: [Bool] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private let holdBeforeReadCommit: Set<Int>
    private let holdAfterReadCommit: Set<Int>

    init(holdFirstRun: Bool) {
        holdBeforeReadCommit = []
        holdAfterReadCommit = holdFirstRun ? [1] : []
    }

    init(holdBeforeReadCommit: Set<Int> = [], holdAfterReadCommit: Set<Int> = []) {
        self.holdBeforeReadCommit = holdBeforeReadCommit
        self.holdAfterReadCommit = holdAfterReadCommit
    }

    var callCount: Int { calls.count }

    func run(trigger: Trigger, options: RunOptions, onReadCommitted: @escaping @Sendable () -> Void) async -> RunOutcome {
        calls.append((trigger, options))
        cancelledAtStart.append(Task.isCancelled)
        let runNumber = calls.count
        if holdBeforeReadCommit.contains(runNumber) {
            await withCheckedContinuation { gates[runNumber] = $0 }
        }
        onReadCommitted()
        if holdAfterReadCommit.contains(runNumber) {
            await withCheckedContinuation { gates[runNumber] = $0 }
        }
        return RunOutcome(readOutcome: .read, daysWritten: runNumber, daysFailed: 0, daysPending: 0, errors: [])
    }

    func release(run runNumber: Int = 1) {
        gates[runNumber]?.resume()
        gates[runNumber] = nil
    }
}

final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

@Suite struct TriggerCoordinatorTests {
    @Test func aSingleRequestRunsOnceAndCallsBackOnce() async {
        let runner = GatedRunner(holdFirstRun: false)
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let outcome = await coordinator.request(.observerWake) { callbacks.increment() }

        #expect(await runner.callCount == 1)
        #expect(callbacks.value == 1)
        #expect(outcome.daysWritten == 1)
    }

    @Test func requestsDuringARunCoalesceIntoOneFollowUp() async throws {
        let runner = GatedRunner(holdFirstRun: true)
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount > 0 }
        let followers = (0..<3).map { _ in
            Task { await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount >= 3 }
        await runner.release()

        _ = await first.value
        var followerOutcomes: [RunOutcome] = []
        for follower in followers { followerOutcomes.append(await follower.value) }

        #expect(await runner.callCount == 2)
        #expect(callbacks.value == 3)
        #expect(await runner.calls[1].options == RunOptions(read: true, verify: .none, markAllDirty: false))
        #expect(followerOutcomes.allSatisfy { $0.daysWritten == 2 })
    }

    @Test func mergedOptionsTakeTheWidestScope() async throws {
        let runner = GatedRunner(holdFirstRun: true)
        let coordinator = TriggerCoordinator(runner: runner)

        let first = Task { await coordinator.request(.observerWake) }
        try await waitUntil { await runner.callCount > 0 }
        let intent = Task { await coordinator.request(.appIntent) }
        try await waitUntil { await coordinator.pendingRequestCount >= 1 }
        let rebuild = Task { await coordinator.request(.rebuildAll) }
        try await waitUntil { await coordinator.pendingRequestCount >= 2 }
        await runner.release()
        _ = await first.value
        _ = await intent.value
        _ = await rebuild.value

        #expect(await runner.calls[1].options == RunOptions(read: true, verify: .allDates, markAllDirty: true))
    }

    @Test func requestsDuringTheFollowUpFormAThirdRun() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1, 2])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let secondBatch = (0..<2).map { _ in
            Task { await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        let thirdCallbacks = Counter()
        let third = Task { await coordinator.request(.observerWake) { thirdCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 2)
        try await waitUntil { await runner.callCount == 3 }
        await runner.release(run: 3)

        _ = await first.value
        for follower in secondBatch { #expect(await follower.value.daysWritten == 2) }
        #expect(await third.value.daysWritten == 3)
        #expect(await runner.callCount == 3)
        #expect(callbacks.value == 2)
        #expect(thirdCallbacks.value == 1)
        #expect(await coordinator.pendingRequestCount == 0)
    }

    @Test func followerCallbacksWaitForTheFollowUpReadCommit() async throws {
        let runner = GatedRunner(holdBeforeReadCommit: [2], holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let followers = (0..<2).map { _ in
            Task { await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        #expect(callbacks.value == 0)
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        #expect(callbacks.value == 0)
        await runner.release(run: 2)

        _ = await first.value
        for follower in followers { _ = await follower.value }
        #expect(callbacks.value == 2)
    }

    @Test func aCancelledRequesterDoesNotCancelTheQueuedFollowUp() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { await coordinator.request(.appOpen) }
        try await waitUntil { await runner.callCount == 1 }
        let follower = Task { await coordinator.request(.observerWake) { callbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        first.cancel()
        await runner.release(run: 1)

        _ = await first.value
        let followerOutcome = await follower.value

        #expect(await runner.callCount == 2)
        #expect(await runner.cancelledAtStart == [false, false])
        #expect(followerOutcome.daysWritten == 2)
        #expect(callbacks.value == 1)
    }
}
