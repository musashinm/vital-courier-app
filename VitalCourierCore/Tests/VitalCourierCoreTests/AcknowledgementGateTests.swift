import Dispatch
import Foundation
import Testing
@testable import VitalCourierCore

struct GateFailure: Error {}

@Suite struct AcknowledgementGateTests {
    /// Calls the gate from a dispatch queue, like HealthKit does, so the blocking wait never sits on the cooperative pool.
    func waitOnBackgroundQueue(
        timeout: DispatchTimeInterval,
        onFailure: @escaping @Sendable (String) -> Void = { _ in },
        work: @escaping @Sendable (_ signal: @escaping @Sendable () -> Void) async throws -> Void
    ) async -> AcknowledgementOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: AcknowledgementGate.wait(timeout: timeout, onFailure: onFailure, work: work))
            }
        }
    }

    @Test func aSignalAcknowledgesWhileTheWorkIsStillRunning() async throws {
        let latch = Latch()
        let finished = Counter()

        let outcome = await waitOnBackgroundQueue(timeout: .seconds(10)) { signal in
            signal()
            await latch.wait()
            finished.increment()
        }

        #expect(outcome == .signaled)
        #expect(finished.value == 0)
        await latch.open()
        try await waitUntil { finished.value == 1 }
    }

    @Test func workThatReturnsWithoutASignalStillAcknowledges() async {
        let outcome = await waitOnBackgroundQueue(timeout: .seconds(10)) { _ in }

        #expect(outcome == .signaled)
    }

    @Test func aFailureBeforeTheSignalEndsTheWaitAtOnceAndIsReported() async {
        let failures = EventLog()
        let clock = ContinuousClock()
        var outcome: AcknowledgementOutcome?

        let elapsed = await clock.measure {
            outcome = await waitOnBackgroundQueue(timeout: .seconds(30), onFailure: { failures.append($0) }) { _ in
                throw GateFailure()
            }
        }

        #expect(outcome == .failed("GateFailure()"))
        #expect(failures.all == ["GateFailure()"])
        #expect(elapsed < .seconds(5))
    }

    @Test func aBlockedFailureReporterDoesNotDelayAnImmediateFailure() async {
        let reporterRelease = DispatchSemaphore(value: 0)

        let outcome = await waitOnBackgroundQueue(timeout: .seconds(1), onFailure: { _ in
            _ = reporterRelease.wait(timeout: .now() + .seconds(10))
        }) { _ in
            throw GateFailure()
        }
        reporterRelease.signal()

        #expect(outcome == .failed("GateFailure()"))
    }

    @Test func aTimeoutAcknowledgesAndTheWorkKeepsRunning() async throws {
        let latch = Latch()
        let finished = Counter()
        let failures = EventLog()

        let outcome = await waitOnBackgroundQueue(timeout: .milliseconds(50), onFailure: { failures.append($0) }) { _ in
            await latch.wait()
            finished.increment()
        }

        #expect(outcome == .timedOut)
        #expect(finished.value == 0)
        await latch.open()
        try await waitUntil { finished.value == 1 }
        #expect(failures.all.isEmpty)
    }

    @Test func aFailureAfterTheSignalIsStillReported() async throws {
        let failures = EventLog()

        let outcome = await waitOnBackgroundQueue(timeout: .seconds(10), onFailure: { failures.append($0) }) { signal in
            signal()
            throw GateFailure()
        }

        #expect(outcome == .signaled)
        try await waitUntil { failures.all == ["GateFailure()"] }
    }

    @Test func aFailureAfterATimeoutIsStillReported() async throws {
        let latch = Latch()
        let failures = EventLog()

        let outcome = await waitOnBackgroundQueue(timeout: .milliseconds(50), onFailure: { failures.append($0) }) { _ in
            await latch.wait()
            throw GateFailure()
        }

        #expect(outcome == .timedOut)
        await latch.open()
        try await waitUntil { failures.all == ["GateFailure()"] }
    }
}
