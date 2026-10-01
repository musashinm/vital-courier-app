import Foundation

public protocol ExportRunning: Sendable {
    func run(trigger: Trigger, options: RunOptions, onReadCommitted: @escaping @Sendable () -> Void) async -> RunOutcome
}

extension ExportRunner: ExportRunning {}

/// Every trigger asks this actor for a run (spec, Units: TriggerCoordinator). One run at a time; requests that arrive mid-run merge into one follow-up run.
public actor TriggerCoordinator {
    private struct PendingRun {
        var trigger: Trigger
        var options: RunOptions
        var readCallbacks: [@Sendable () -> Void]
        var waiters: [CheckedContinuation<RunOutcome, Never>]
    }

    private let runner: any ExportRunning
    private var isRunning = false
    private var pending: PendingRun?

    public init(runner: any ExportRunning) {
        self.runner = runner
    }

    var pendingRequestCount: Int { pending?.waiters.count ?? 0 }

    public func request(_ trigger: Trigger, onReadCommitted: @escaping @Sendable () -> Void = {}) async -> RunOutcome {
        let options = RunOptions.forTrigger(trigger)
        guard !isRunning else {
            return await withCheckedContinuation { continuation in
                if var queued = pending {
                    queued.options = queued.options.merged(with: options)
                    queued.readCallbacks.append(onReadCommitted)
                    queued.waiters.append(continuation)
                    pending = queued
                } else {
                    pending = PendingRun(trigger: trigger, options: options, readCallbacks: [onReadCommitted], waiters: [continuation])
                }
            }
        }
        isRunning = true
        let outcome = await runner.run(trigger: trigger, options: options, onReadCommitted: onReadCommitted)
        while let next = pending {
            pending = nil
            let callbacks = next.readCallbacks
            let followUp = await runner.run(trigger: next.trigger, options: next.options) {
                for callback in callbacks { callback() }
            }
            for waiter in next.waiters { waiter.resume(returning: followUp) }
        }
        isRunning = false
        return outcome
    }
}
