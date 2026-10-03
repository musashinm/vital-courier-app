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
    private(set) var activeRuns = 0
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
        activeRuns += 1
        defer { activeRuns -= 1 }
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

struct ClearFailed: Error {}

/// Holds the coordinator inside its handoff window until the test opens it.
actor HandoffGate {
    private(set) var hasArrived = false
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func arriveAndWait() async {
        hasArrived = true
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

@Suite struct TriggerCoordinatorTests {
    @Test func aSingleRequestRunsOnceAndCallsBackOnce() async throws {
        let runner = GatedRunner(holdFirstRun: false)
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let outcome = try await coordinator.request(.observerWake) { callbacks.increment() }

        #expect(await runner.callCount == 1)
        #expect(callbacks.value == 1)
        #expect(outcome.daysWritten == 1)
    }

    @Test func requestsDuringARunCoalesceIntoOneFollowUp() async throws {
        let runner = GatedRunner(holdFirstRun: true)
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount > 0 }
        let followers = (0..<3).map { _ in
            Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount >= 3 }
        await runner.release()

        _ = try await first.value
        var followerOutcomes: [RunOutcome] = []
        for follower in followers { followerOutcomes.append(try await follower.value) }

        #expect(await runner.callCount == 2)
        #expect(callbacks.value == 3)
        #expect(await runner.calls[1].options == RunOptions(read: true, verify: .none, markAllDirty: false))
        #expect(followerOutcomes.allSatisfy { $0.daysWritten == 2 })
    }

    @Test func mergedOptionsTakeTheWidestScope() async throws {
        let runner = GatedRunner(holdFirstRun: true)
        let coordinator = TriggerCoordinator(runner: runner)

        let first = Task { try await coordinator.request(.observerWake) }
        try await waitUntil { await runner.callCount > 0 }
        let intent = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await coordinator.pendingRequestCount >= 1 }
        let rebuild = Task { try await coordinator.request(.rebuildAll) }
        try await waitUntil { await coordinator.pendingRequestCount >= 2 }
        await runner.release()
        _ = try await first.value
        _ = try await intent.value
        _ = try await rebuild.value

        #expect(await runner.calls[1].options == RunOptions(read: true, verify: .allDates, markAllDirty: true))
    }

    @Test func requestsDuringTheFollowUpFormAThirdRun() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1, 2])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let secondBatch = (0..<2).map { _ in
            Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        let thirdCallbacks = Counter()
        let third = Task { try await coordinator.request(.observerWake) { thirdCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 2)
        try await waitUntil { await runner.callCount == 3 }
        await runner.release(run: 3)

        _ = try await first.value
        for follower in secondBatch { #expect(try await follower.value.daysWritten == 2) }
        #expect(try await third.value.daysWritten == 3)
        #expect(await runner.callCount == 3)
        #expect(callbacks.value == 2)
        #expect(thirdCallbacks.value == 1)
        #expect(await coordinator.pendingRequestCount == 0)
    }

    @Test func followerCallbacksWaitForTheFollowUpReadCommit() async throws {
        let runner = GatedRunner(holdBeforeReadCommit: [2], holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let followers = (0..<2).map { _ in
            Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        #expect(callbacks.value == 0)
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        #expect(callbacks.value == 0)
        await runner.release(run: 2)

        _ = try await first.value
        for follower in followers { _ = try await follower.value }
        #expect(callbacks.value == 2)
    }

    @Test func aCancelledRequesterDoesNotCancelTheQueuedFollowUp() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appOpen) }
        try await waitUntil { await runner.callCount == 1 }
        let follower = Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        first.cancel()
        await runner.release(run: 1)

        _ = try await first.value
        let followerOutcome = try await follower.value

        #expect(await runner.callCount == 2)
        #expect(await runner.cancelledAtStart == [false, false])
        #expect(followerOutcome.daysWritten == 2)
        #expect(callbacks.value == 1)
    }

    @Test func aCancelledQueuedRequestLeavesTheQueueAndOthersStillRun() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let refreshCallbacks = Counter()
        let observerCallbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let refresh = Task { try await coordinator.request(.backgroundRefresh) { refreshCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        let observer = Task { try await coordinator.request(.observerWake) { observerCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        refresh.cancel()
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 1)

        _ = try await first.value
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(try await observer.value.daysWritten == 2)
        #expect(await runner.callCount == 2)
        #expect(await runner.calls[1].trigger == .observerWake)
        #expect(await runner.calls[1].options == RunOptions.forTrigger(.observerWake))
        #expect(refreshCallbacks.value == 0)
        #expect(observerCallbacks.value == 1)
    }

    @Test func theOnlyQueuedRequestCancelledMeansNoFollowUp() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)

        let first = Task { try await coordinator.request(.appOpen) }
        try await waitUntil { await runner.callCount == 1 }
        let refresh = Task { try await coordinator.request(.backgroundRefresh) }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        refresh.cancel()
        try await waitUntil { await coordinator.pendingRequestCount == 0 }
        await runner.release(run: 1)

        _ = try await first.value
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await runner.callCount == 1)
    }

    @Test func anObserverQueuedBehindRebuildAllIsAcknowledgedBeforeTheRebuildFinishes() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let rebuild = Task { try await coordinator.request(.rebuildAll) }
        try await waitUntil { await runner.callCount == 1 }
        let observer = Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        // The handler is called while the rebuild is still held, and the request stays queued for its own read.
        try await waitUntil { callbacks.value == 1 }
        #expect(await runner.activeRuns == 1)
        #expect(await coordinator.pendingRequestCount == 1)
        await runner.release(run: 1)

        _ = try await rebuild.value
        #expect(try await observer.value.daysWritten == 2)
        #expect(await runner.callCount == 2)
        #expect(await runner.calls[1].trigger == .observerWake)
        #expect(callbacks.value == 1)
    }

    @Test func anObserverQueuedDuringARebuildFollowUpIsAcknowledgedAtOnce() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1, 2])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let rebuild = Task { try await coordinator.request(.rebuildAll) }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        let observer = Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        try await waitUntil { callbacks.value == 1 }
        #expect(await runner.activeRuns == 1)
        await runner.release(run: 2)

        _ = try await first.value
        _ = try await rebuild.value
        _ = try await observer.value
        #expect(await runner.callCount == 3)
        #expect(callbacks.value == 1)
    }

    @Test func anObserverArrivingInTheHandoffToARebuildFollowUpIsAcknowledgedAtOnce() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let gate = HandoffGate()
        let coordinator = TriggerCoordinator(runner: runner, beforeFollowUpHandoff: { await gate.arriveAndWait() })
        let callbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let rebuild = Task { try await coordinator.request(.rebuildAll) }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 1)
        // Run 1 has returned and the coordinator sits between it and the Rebuild all follow-up.
        try await waitUntil { await gate.hasArrived }
        #expect(await runner.callCount == 1)
        let observer = Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        try await waitUntil { callbacks.value == 1 }
        #expect(await coordinator.pendingRequestCount == 1)
        await gate.open()

        _ = try await first.value
        _ = try await rebuild.value
        _ = try await observer.value
        #expect(await runner.callCount == 3)
        #expect(await runner.calls[1].options.markAllDirty)
        #expect(await runner.calls[2].trigger == .observerWake)
        #expect(callbacks.value == 1)
    }

    @Test func anObserverAcknowledgedBehindRebuildAllThenCancelledIsAcknowledgedOnceAndNeverRuns() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let coordinator = TriggerCoordinator(runner: runner)
        let callbacks = Counter()

        let rebuild = Task { try await coordinator.request(.rebuildAll) }
        try await waitUntil { await runner.callCount == 1 }
        let observer = Task { try await coordinator.request(.observerWake) { callbacks.increment() } }
        try await waitUntil { callbacks.value == 1 }
        #expect(await coordinator.pendingRequestCount == 1)
        observer.cancel()
        try await waitUntil { await coordinator.pendingRequestCount == 0 }
        await runner.release(run: 1)

        _ = try await rebuild.value
        await #expect(throws: CancellationError.self) { try await observer.value }
        #expect(await runner.callCount == 1)
        #expect(callbacks.value == 1)
    }

    @Test func aRequestCancelledInTheHandoffWindowNeverRuns() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let gate = HandoffGate()
        let recordedCancellations = Counter()
        let coordinator = TriggerCoordinator(runner: runner, beforeFollowUpHandoff: { await gate.arriveAndWait() }, afterDequeuedCancellationRecorded: { recordedCancellations.increment() })
        let refreshCallbacks = Counter()
        let observerCallbacks = Counter()

        let first = Task { try await coordinator.request(.appIntent) }
        try await waitUntil { await runner.callCount == 1 }
        let refresh = Task { try await coordinator.request(.backgroundRefresh) { refreshCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        let observer = Task { try await coordinator.request(.observerWake) { observerCallbacks.increment() } }
        try await waitUntil { await coordinator.pendingRequestCount == 2 }
        await runner.release(run: 1)
        // The batch has left the queue and has not started: both requests are in the handoff window.
        try await waitUntil { await gate.hasArrived }
        #expect(await coordinator.pendingRequestCount == 0)
        observer.cancel()
        // Cancellation reaches the actor through an unstructured task; wait until the coordinator has recorded it before the window closes.
        try await waitUntil { recordedCancellations.value == 1 }
        await gate.open()

        _ = try await first.value
        await #expect(throws: CancellationError.self) { try await observer.value }
        #expect(try await refresh.value.daysWritten == 2)
        #expect(await runner.callCount == 2)
        #expect(await runner.calls[1].trigger == .backgroundRefresh)
        #expect(observerCallbacks.value == 0)
        #expect(refreshCallbacks.value == 1)
    }

    @Test func aWholeBatchCancelledInTheHandoffWindowMeansNoFollowUp() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1])
        let gate = HandoffGate()
        let recordedCancellations = Counter()
        let coordinator = TriggerCoordinator(runner: runner, beforeFollowUpHandoff: { await gate.arriveAndWait() }, afterDequeuedCancellationRecorded: { recordedCancellations.increment() })

        let first = Task { try await coordinator.request(.appOpen) }
        try await waitUntil { await runner.callCount == 1 }
        let observer = Task { try await coordinator.request(.observerWake) }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        await runner.release(run: 1)
        try await waitUntil { await gate.hasArrived }
        observer.cancel()
        try await waitUntil { recordedCancellations.value == 1 }
        await gate.open()

        _ = try await first.value
        await #expect(throws: CancellationError.self) { try await observer.value }
        #expect(await runner.callCount == 1)
        #expect(await coordinator.pendingRequestCount == 0)
        // The coordinator is idle again, not stuck running.
        #expect(try await coordinator.exclusive { 7 } == 7)
    }

    @Test func exclusiveWaitsForTheRunAndItsFollowUp() async throws {
        let runner = GatedRunner(holdAfterReadCommit: [1, 2])
        let coordinator = TriggerCoordinator(runner: runner)
        let bodyRuns = Counter()

        let first = Task { try await coordinator.request(.observerWake) }
        try await waitUntil { await runner.callCount == 1 }
        let follower = Task { try await coordinator.request(.observerWake) }
        try await waitUntil { await coordinator.pendingRequestCount == 1 }
        let clear = Task {
            try await coordinator.exclusive {
                bodyRuns.increment()
            }
        }
        // The body can only have run by now if `exclusive` did not wait, so this check cannot pass vacuously.
        try await waitUntil { await coordinator.idleWaiterCount == 1 }
        #expect(bodyRuns.value == 0)
        await runner.release(run: 1)
        try await waitUntil { await runner.callCount == 2 }
        // `isRunning` stays true through the follow-up, so the waiter is still registered and the body has not run.
        #expect(await coordinator.idleWaiterCount == 1)
        #expect(bodyRuns.value == 0)
        await runner.release(run: 2)

        try await clear.value
        _ = try await first.value
        _ = try await follower.value
        #expect(bodyRuns.value == 1)
        #expect(await runner.activeRuns == 0)
    }

    @Test func exclusiveRunsAtOnceWhenIdleAndRethrows() async throws {
        let coordinator = TriggerCoordinator(runner: GatedRunner(holdFirstRun: false))

        #expect(try await coordinator.exclusive { 42 } == 42)
        await #expect(throws: ClearFailed.self) {
            try await coordinator.exclusive { throw ClearFailed() }
        }
    }
}
