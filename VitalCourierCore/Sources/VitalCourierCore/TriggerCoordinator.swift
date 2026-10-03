import Foundation

public protocol ExportRunning: Sendable {
    func run(trigger: Trigger, options: RunOptions, onReadCommitted: @escaping @Sendable () -> Void) async -> RunOutcome
}

extension ExportRunner: ExportRunning {}

/// Every trigger asks this actor for a run (spec, Units: TriggerCoordinator). One run at a time; requests that arrive mid-run merge into one follow-up run. A queued request whose task is cancelled leaves the queue, so an expired `BGAppRefreshTask` doesn't run later inside someone else's follow-up.
public actor TriggerCoordinator {
    private struct QueuedRequest {
        let id: UInt64
        let trigger: Trigger
        let options: RunOptions
        let onReadCommitted: @Sendable () -> Void
        let continuation: CheckedContinuation<RunOutcome, any Error>
    }

    private let runner: any ExportRunning
    private var isRunning = false
    /// True while the active run has `markAllDirty` (Rebuild all). It verifies and rewrites every file, so it can outlast the time iOS tolerates an unacknowledged observer callback.
    private var isMaintenanceRunActive = false
    private var queue: [QueuedRequest] = []
    /// IDs of requests taken into a batch that has not started yet, and the subset of those whose task was cancelled meanwhile. A cancelled one is resumed with `CancellationError` just before its batch starts, so the handoff window cannot let it run.
    private var dequeuedRequestIDs: Set<UInt64> = []
    private var cancelledDequeuedRequestIDs: Set<UInt64> = []
    private var nextRequestID: UInt64 = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// Test seam: awaited after the follow-up batch is taken and before it runs, the one point where the requesting task is suspended and new requests can still arrive.
    private let beforeFollowUpHandoff: (@Sendable () async -> Void)?
    /// Test seam: called when a cancellation of an already dequeued request has been recorded, so a test can wait for the cancellation to land before it opens the handoff gate.
    private let afterDequeuedCancellationRecorded: (@Sendable () -> Void)?

    public init(runner: any ExportRunning) {
        self.runner = runner
        beforeFollowUpHandoff = nil
        afterDequeuedCancellationRecorded = nil
    }

    init(runner: any ExportRunning, beforeFollowUpHandoff: (@Sendable () async -> Void)?, afterDequeuedCancellationRecorded: (@Sendable () -> Void)? = nil) {
        self.runner = runner
        self.beforeFollowUpHandoff = beforeFollowUpHandoff
        self.afterDequeuedCancellationRecorded = afterDequeuedCancellationRecorded
    }

    var pendingRequestCount: Int { queue.count }
    /// Test seam: how many `exclusive` callers are registered and waiting for the coordinator to go idle.
    var idleWaiterCount: Int { idleWaiters.count }

    /// Throws `CancellationError` only when the caller's task is cancelled before its run starts (still queued, or taken into a batch that has not started); its `onReadCommitted` is then never called later. A request that started running always returns its outcome. Behind a maintenance run the request still queues for its own anchored read, but `onReadCommitted` is called on arrival (the observer handler must not wait for a Rebuild all).
    public func request(_ trigger: Trigger, onReadCommitted: @escaping @Sendable () -> Void = {}) async throws -> RunOutcome {
        let options = RunOptions.forTrigger(trigger)
        guard !isRunning else {
            nextRequestID += 1
            let requestID = nextRequestID
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    var queuedCallback = onReadCommitted
                    if isMaintenanceRunActive {
                        onReadCommitted()
                        queuedCallback = {}
                    }
                    queue.append(QueuedRequest(id: requestID, trigger: trigger, options: options, onReadCommitted: queuedCallback, continuation: continuation))
                }
            } onCancel: {
                Task { await self.dropQueuedRequest(id: requestID) }
            }
        }
        isRunning = true
        isMaintenanceRunActive = options.markAllDirty
        let outcome = await runner.run(trigger: trigger, options: options, onReadCommitted: onReadCommitted)
        // Taking the next batch and setting `isMaintenanceRunActive` for it happen in one synchronous step, so a request arriving while this task is suspended below already sees the follow-up's flag.
        guard let firstFollowUp = takeNextBatch() else { return outcome }
        await beforeFollowUpHandoff?()
        // Follow-up runs go through a fresh unstructured task, which does not inherit this requester's cancellation.
        await Task { await self.drainQueuedRequests(startingWith: firstFollowUp) }.value
        return outcome
    }

    /// Runs `body` while no run is active and nothing is queued (Clear local copy must never delete rows a run is writing). `body` is synchronous on this actor, so no request can start while it runs.
    public func exclusive<Value: Sendable>(_ body: @Sendable () throws -> Value) async throws -> Value {
        while isRunning {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        return try body()
    }

    /// Takes the whole queue as the next batch and sets `isMaintenanceRunActive` from the batch's merged options, with no suspension in between. With an empty queue it ends the run state instead (`isRunning` false, idle waiters resumed) and returns nil.
    private func takeNextBatch() -> [QueuedRequest]? {
        guard !queue.isEmpty else {
            isRunning = false
            isMaintenanceRunActive = false
            let waiters = idleWaiters
            idleWaiters = []
            for waiter in waiters { waiter.resume() }
            return nil
        }
        let batch = queue
        queue = []
        dequeuedRequestIDs.formUnion(batch.map(\.id))
        isMaintenanceRunActive = Self.mergedOptions(of: batch).markAllDirty
        return batch
    }

    private static func mergedOptions(of batch: [QueuedRequest]) -> RunOptions {
        batch.dropFirst().reduce(batch[0].options) { $0.merged(with: $1.options) }
    }

    private func drainQueuedRequests(startingWith firstBatch: [QueuedRequest]) async {
        var batch: [QueuedRequest]? = firstBatch
        while let taken = batch {
            let current = startableRequests(in: taken)
            guard !current.isEmpty else {
                batch = takeNextBatch()
                continue
            }
            let callbacks = current.map(\.onReadCommitted)
            let followUp = await runner.run(trigger: current[0].trigger, options: Self.mergedOptions(of: current)) {
                for callback in callbacks { callback() }
            }
            for request in current { request.continuation.resume(returning: followUp) }
            batch = takeNextBatch()
        }
    }

    /// Resumes the batch's cancelled requests with `CancellationError` and returns the rest, in one synchronous step with the batch about to start. The maintenance flag is recomputed from what will actually run.
    private func startableRequests(in taken: [QueuedRequest]) -> [QueuedRequest] {
        var startable: [QueuedRequest] = []
        for request in taken {
            dequeuedRequestIDs.remove(request.id)
            if cancelledDequeuedRequestIDs.remove(request.id) != nil {
                request.continuation.resume(throwing: CancellationError())
            } else {
                startable.append(request)
            }
        }
        if !startable.isEmpty { isMaintenanceRunActive = Self.mergedOptions(of: startable).markAllDirty }
        return startable
    }

    private func dropQueuedRequest(id: UInt64) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index).continuation.resume(throwing: CancellationError())
        } else if dequeuedRequestIDs.contains(id) {
            cancelledDequeuedRequestIDs.insert(id)
            afterDequeuedCancellationRecorded?()
        }
    }
}
