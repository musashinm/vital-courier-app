import Synchronization

/// A callback that runs at most once, whichever path calls it first. Used by `AcknowledgementGate` so its acknowledgement signal fires once (the observer completion handler itself cannot go through it: it is not `Sendable`, see Task 10).
public final class OnceCallback: Sendable {
    private let callback: Mutex<(@Sendable () -> Void)?>

    public init(_ callback: @escaping @Sendable () -> Void) {
        self.callback = Mutex(callback)
    }

    public func callAsFunction() {
        let pending = callback.withLock { stored -> (@Sendable () -> Void)? in
            let current = stored
            stored = nil
            return current
        }
        pending?()
    }
}
