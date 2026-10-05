import Dispatch
import Foundation
import Synchronization
import Testing
@testable import VitalCourierCore

struct WakeRunFailure: Error {}

/// Stands in for `UIApplication` background time: records begins and ends, and expires on demand.
final class FakeBackgroundTime: Sendable {
    private let expiryHandler = Mutex<(@Sendable () -> Void)?>(nil)
    private let endedTokens = Mutex<[Int]>([])
    let grantedToken: Int?
    let expiresDuringBegin: Bool

    init(grantedToken: Int? = 7, expiresDuringBegin: Bool = false) {
        self.grantedToken = grantedToken
        self.expiresDuringBegin = expiresDuringBegin
    }

    func begin(_ onExpire: @escaping @Sendable () -> Void) -> Int? {
        expiryHandler.withLock { $0 = onExpire }
        if expiresDuringBegin { onExpire() }
        return grantedToken
    }

    func end(_ token: Int) { endedTokens.withLock { $0.append(token) } }
    func expire() { expiryHandler.withLock { $0 }?() }
    var ends: [Int] { endedTokens.withLock { $0 } }
}

final class TextLog: Sendable {
    private let entries = Mutex<[String]>([])
    func append(_ text: String) { entries.withLock { $0.append(text) } }
    var values: [String] { entries.withLock { $0 } }
}

/// A run that only ends by cancellation, counting when it sees it. Tests wait on the count with `waitUntil` (2 s), so a broken cancel fails fast instead of passing after the sleep.
func runUntilCancelled(_ observedCancellation: Counter) async throws {
    do {
        try await Task.sleep(for: .seconds(30))
    } catch {
        observedCancellation.increment()
        throw error
    }
}

@Suite struct ObserverWakeTests {
    func startWake(
        _ time: FakeBackgroundTime,
        failures: TextLog = TextLog(),
        cutShort: @escaping @Sendable () -> Void = {},
        beforeRegistration: () -> Void = {},
        beforeCompletion: @escaping @Sendable () async -> Void = {},
        run: @escaping @Sendable () async throws -> Void
    ) -> ObserverWake {
        ObserverWake.start(
            beginBackgroundTime: time.begin,
            endBackgroundTime: time.end,
            onFailure: failures.append,
            onCutShort: cutShort,
            beforeRegistration: beforeRegistration,
            beforeCompletion: beforeCompletion,
            run: run
        )
    }

    @Test func startReturnsBeforeTheRunFinishes() async throws {
        let time = FakeBackgroundTime()
        let latch = Latch()
        let finished = Counter()

        _ = startWake(time) {
            await latch.wait()
            finished.increment()
        }

        #expect(finished.value == 0)
        #expect(time.ends.isEmpty)
        await latch.open()
        try await waitUntil { time.ends == [7] }
        #expect(finished.value == 1)
    }

    @Test func aReturnedRunEndsTheTokenOnceAndIsNotCutShort() async {
        let time = FakeBackgroundTime()
        let cutShort = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) {}
        await wake.untilRunFinishes()

        #expect(time.ends == [7])
        #expect(cutShort.value == 0)
    }

    @Test func aThrownRunEndsTheTokenOnceAndReportsTheError() async {
        let time = FakeBackgroundTime()
        let failures = TextLog()
        let cutShort = Counter()

        let wake = startWake(time, failures: failures, cutShort: cutShort.increment) { throw WakeRunFailure() }
        await wake.untilRunFinishes()

        #expect(time.ends == [7])
        #expect(failures.values == ["WakeRunFailure()"])
        #expect(cutShort.value == 0)
    }

    @Test func aCancelledRunEndsTheTokenOnceIsCutShortAndIsNotAFailure() async throws {
        let time = FakeBackgroundTime()
        let failures = TextLog()
        let cutShort = Counter()

        let wake = startWake(time, failures: failures, cutShort: cutShort.increment) { throw CancellationError() }
        await wake.untilRunFinishes()

        #expect(time.ends == [7])
        #expect(failures.values.isEmpty)
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func expiryEndsTheTokenAtOnceCancelsTheRunAndIsCutShortOnce() async throws {
        let time = FakeBackgroundTime()
        let cutShort = Counter()
        let observedCancellation = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) { try await runUntilCancelled(observedCancellation) }
        time.expire()

        #expect(time.ends == [7])
        try await waitUntil { observedCancellation.value == 1 }
        await wake.untilRunFinishes()
        #expect(time.ends == [7])
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func withoutATokenTheRunStillRunsAndNothingEnds() async {
        let time = FakeBackgroundTime(grantedToken: nil)
        let latch = Latch()
        let finished = Counter()
        let cutShort = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) {
            await latch.wait()
            finished.increment()
        }
        time.expire()
        await latch.open()
        await wake.untilRunFinishes()

        #expect(finished.value == 1)
        #expect(time.ends.isEmpty)
        #expect(cutShort.value == 0)
    }

    @Test func expiryDuringBeginEndsOnceAndCancelsTheRun() async throws {
        let time = FakeBackgroundTime(expiresDuringBegin: true)
        let cutShort = Counter()
        let observedCancellation = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) { try await runUntilCancelled(observedCancellation) }

        #expect(time.ends == [7])
        try await waitUntil { observedCancellation.value == 1 }
        await wake.untilRunFinishes()
        #expect(time.ends == [7])
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func expiryBeforeRegistrationCancelsTheRunAtRegistration() async throws {
        let time = FakeBackgroundTime()
        let cutShort = Counter()
        let observedCancellation = Counter()

        let wake = startWake(time, cutShort: cutShort.increment, beforeRegistration: { time.expire() }) {
            try await runUntilCancelled(observedCancellation)
        }

        #expect(time.ends == [7])
        try await waitUntil { observedCancellation.value == 1 }
        await wake.untilRunFinishes()
        #expect(time.ends == [7])
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func expiryAfterCompletionEndsNothingMore() async {
        let time = FakeBackgroundTime()
        let cutShort = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) {}
        await wake.untilRunFinishes()
        time.expire()

        #expect(time.ends == [7])
        #expect(cutShort.value == 0)
    }

    @Test func completionAfterExpiryEndsNothingMore() async throws {
        let time = FakeBackgroundTime()
        let latch = Latch()
        let cutShort = Counter()

        let wake = startWake(time, cutShort: cutShort.increment) { await latch.wait() }
        time.expire()
        await latch.open()
        await wake.untilRunFinishes()

        #expect(time.ends == [7])
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func expiryBetweenTheRunReturningAndItsCompletionIsStillCutShort() async throws {
        let time = FakeBackgroundTime()
        let cutShort = Counter()

        let wake = startWake(time, cutShort: cutShort.increment, beforeCompletion: { time.expire() }) {}
        await wake.untilRunFinishes()

        #expect(time.ends == [7])
        try await waitUntil { cutShort.value == 1 }
    }

    @Test func aBlockedCutShortCallbackNeitherBlocksExpiryNorHoldsTheLock() async throws {
        let time = FakeBackgroundTime()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let arrived = Counter()
        let endsSeenByCallback = TextLog()
        let observedCancellation = Counter()
        let runFinished = Counter()

        // The callback blocks one cooperative-pool thread on purpose, to stand in for a slow callback; the 2 s `waitUntil` bounds keep a starved pool from hanging the suite.
        let wake = startWake(time, cutShort: {
            endsSeenByCallback.append("\(time.ends)")
            arrived.increment()
            release.wait()
        }) { try await runUntilCancelled(observedCancellation) }
        // Returns although the callback will block: the callback runs in its own task.
        time.expire()
        try await waitUntil { arrived.value == 1 }

        #expect(endsSeenByCallback.values == ["[7]"])
        // The run can finish, which takes the lock, while the callback is still blocked.
        Task { await wake.untilRunFinishes(); runFinished.increment() }
        try await waitUntil { runFinished.value == 1 }
        #expect(time.ends == [7])
    }
}
