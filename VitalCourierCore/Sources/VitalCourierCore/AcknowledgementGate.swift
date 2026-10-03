import Dispatch
import Synchronization

/// How `AcknowledgementGate.wait` ended.
public enum AcknowledgementOutcome: Equatable, Sendable {
    /// The work signalled that its read committed, or finished without signalling.
    case signaled
    /// The work threw before it signalled. The text is the error.
    case failed(String)
    /// Nothing happened within the timeout. The work keeps running.
    case timedOut
}

/// Blocks the calling thread until async work says it is safe to acknowledge, with a deadline. The HealthKit observer closure uses it: it cannot hand its non-Sendable completion handler to a `Task`, so it waits here and calls the handler itself afterwards.
///
/// Apple keeps an app that was woken in the background running until the observer's completion handler is called, so waiting here is how the app gets time to commit the read. The price: HealthKit runs every handler on the same anonymous queue, so a wait delays the next handler, and a timeout acknowledges before the read has committed.
public enum AcknowledgementGate {
    /// Runs `work` in a new task and returns as soon as the first of these happens: `work` calls the `signal` it is given, `work` returns, `work` throws, or `timeout` passes. A timeout does not cancel `work`. `onFailure` is called with the error text whenever `work` throws, even after the wait has ended, so no failure goes unreported.
    public static func wait(
        timeout: DispatchTimeInterval,
        onFailure: @escaping @Sendable (String) -> Void,
        work: @escaping @Sendable (_ signal: @escaping @Sendable () -> Void) async throws -> Void
    ) -> AcknowledgementOutcome {
        let semaphore = DispatchSemaphore(value: 0)
        let firstOutcome = Mutex<AcknowledgementOutcome?>(nil)
        let settle: @Sendable (AcknowledgementOutcome) -> Void = { outcome in
            let isFirst = firstOutcome.withLock { current -> Bool in
                guard current == nil else { return false }
                current = outcome
                return true
            }
            if isFirst { semaphore.signal() }
        }
        let signalOnce = OnceCallback { settle(.signaled) }
        Task {
            do {
                try await work { signalOnce() }
            } catch {
                let text = String(describing: error)
                settle(.failed(text))
                onFailure(text)
            }
            settle(.signaled)
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            settle(.timedOut)
        }
        return firstOutcome.withLock { $0 } ?? .timedOut
    }
}
