import Synchronization
import Testing
@testable import VitalCourierCore

private final class FakeTipTransaction: TipTransaction {
    private struct State {
        var finishCount = 0
        var flagWhenFinished: Bool?
    }

    let productID: String
    private let settings: AppSettings
    private let state = Mutex(State())

    init(productID: String, settings: AppSettings) {
        self.productID = productID
        self.settings = settings
    }

    var finishCount: Int { state.withLock { $0.finishCount } }
    var flagWhenFinished: Bool? { state.withLock { $0.flagWhenFinished } }

    func finish() async {
        let flag = settings.hasTipped
        state.withLock {
            $0.finishCount += 1
            $0.flagWhenFinished = flag
        }
    }
}

@Suite struct TipLedgerTests {
    private let settings = AppSettings(storage: InMemoryStorage())

    private func fake(_ productID: String) -> FakeTipTransaction {
        FakeTipTransaction(productID: productID, settings: settings)
    }

    @Test func savesTheFlagBeforeFinishing() async {
        let transaction = fake(TipTier.coffee.productID)
        let recorded = await TipLedger.record(.verified(transaction), in: settings)
        #expect(recorded == true)
        #expect(settings.hasTipped)
        #expect(transaction.finishCount == 1)
        #expect(transaction.flagWhenFinished == true)
    }

    @Test func anUnverifiedTipIsNeitherCountedNorFinished() async {
        let transaction = fake(TipTier.coffee.productID)
        let recorded = await TipLedger.record(.unverified(transaction), in: settings)
        #expect(recorded == false)
        #expect(settings.hasTipped == false)
        #expect(transaction.finishCount == 0)
    }

    @Test func anUnknownProductIsLeftAlone() async {
        let transaction = fake("app.vitalcourier.other")
        let recorded = await TipLedger.record(.verified(transaction), in: settings)
        #expect(recorded == false)
        #expect(settings.hasTipped == false)
        #expect(transaction.finishCount == 0)
    }

    @Test func aVerifiedPurchaseResultIsThanked() async {
        let transaction = fake(TipTier.coffee.productID)
        let outcome = await TipLedger.outcome(of: .success(.verified(transaction)), in: settings)
        #expect(outcome == .thanked)
        #expect(settings.hasTipped)
        #expect(transaction.finishCount == 1)
    }

    @Test func anUnverifiedPurchaseResultFails() async {
        let transaction = fake(TipTier.coffee.productID)
        let outcome = await TipLedger.outcome(of: .success(.unverified(transaction)), in: settings)
        #expect(outcome == .failed)
        #expect(settings.hasTipped == false)
        #expect(transaction.finishCount == 0)
    }

    @Test func aCancelledPurchaseIsNeitherCountedNorFinished() async {
        let outcome = await TipLedger.outcome(of: TipPurchaseResult<FakeTipTransaction>.userCancelled, in: settings)
        #expect(outcome == .cancelled)
        #expect(settings.hasTipped == false)
    }

    @Test func aPendingPurchaseIsNotCounted() async {
        let outcome = await TipLedger.outcome(of: TipPurchaseResult<FakeTipTransaction>.pending, in: settings)
        #expect(outcome == .pending)
        #expect(settings.hasTipped == false)
    }

    @Test func recordEachRecordsAndFinishesEveryVerifiedTip() async {
        let verifiedCoffee = fake(TipTier.coffee.productID)
        let unverifiedSmall = fake(TipTier.smallThanks.productID)
        let verifiedKeepGoing = fake(TipTier.keepGoing.productID)
        let stream = AsyncStream<TipVerification<FakeTipTransaction>> { continuation in
            continuation.yield(.verified(verifiedCoffee))
            continuation.yield(.unverified(unverifiedSmall))
            continuation.yield(.verified(verifiedKeepGoing))
            continuation.finish()
        }
        let recordedCount = Mutex(0)

        await TipLedger.recordEach(stream, in: settings) {
            recordedCount.withLock { $0 += 1 }
        }

        #expect(settings.hasTipped)
        #expect(verifiedCoffee.finishCount == 1)
        #expect(verifiedKeepGoing.finishCount == 1)
        #expect(unverifiedSmall.finishCount == 0)
        #expect(recordedCount.withLock { $0 } == 2)
    }

    @Test func recordEachIgnoresAnEmptySequence() async {
        let stream = AsyncStream<TipVerification<FakeTipTransaction>> { $0.finish() }
        let recordedCount = Mutex(0)

        await TipLedger.recordEach(stream, in: settings) {
            recordedCount.withLock { $0 += 1 }
        }

        #expect(settings.hasTipped == false)
        #expect(recordedCount.withLock { $0 } == 0)
    }
}
