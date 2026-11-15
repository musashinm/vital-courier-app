import Synchronization
import Testing

@testable import VitalCourierCore

private final class FakeTipTransaction: TipTransaction {
  private struct State {
    var finishCount = 0
    var flagWhenFinished: Bool?
    var callbackRanBeforeFinish: Bool?
  }

  let productID: String
  let isRevoked: Bool
  private let settings: AppSettings
  private let onFinish: (@Sendable () -> Void)?
  private let state = Mutex(State())

  init(
    productID: String, settings: AppSettings, isRevoked: Bool = false,
    onFinish: (@Sendable () -> Void)? = nil
  ) {
    self.productID = productID
    self.settings = settings
    self.isRevoked = isRevoked
    self.onFinish = onFinish
  }

  var finishCount: Int { state.withLock { $0.finishCount } }
  var flagWhenFinished: Bool? { state.withLock { $0.flagWhenFinished } }
  var callbackRanBeforeFinish: Bool? { state.withLock { $0.callbackRanBeforeFinish } }

  /// Set by the test's `afterSaving` callback, so `finish()` can tell whether the callback came first.
  func noteCallbackRan() { callbackRan.withLock { $0 = true } }
  private let callbackRan = Mutex(false)

  func finish() async {
    let flag = settings.hasTipped
    let callbackAlreadyRan = callbackRan.withLock { $0 }
    state.withLock {
      $0.finishCount += 1
      $0.flagWhenFinished = flag
      $0.callbackRanBeforeFinish = callbackAlreadyRan
    }
    onFinish?()
  }
}

private func stream(_ items: [TipVerification<FakeTipTransaction>]) -> AsyncStream<TipVerification<FakeTipTransaction>>
{
  AsyncStream { continuation in
    for item in items { continuation.yield(item) }
    continuation.finish()
  }
}

@Suite struct TipLedgerTests {
  private let settings = AppSettings(storage: InMemoryStorage())

  private func fake(_ productID: String, isRevoked: Bool = false) -> FakeTipTransaction {
    FakeTipTransaction(productID: productID, settings: settings, isRevoked: isRevoked)
  }

  @Test func savesTheFlagBeforeFinishing() async {
    let transaction = fake(TipTier.coffee.productID)
    let recorded = await TipLedger.record(.verified(transaction), in: settings) {}
    #expect(recorded == true)
    #expect(settings.hasTipped)
    #expect(transaction.finishCount == 1)
    #expect(transaction.flagWhenFinished == true)
  }

  @Test func runsTheCallbackAfterSavingAndBeforeFinishing() async {
    let transaction = fake(TipTier.coffee.productID)
    let flagWhenCallbackRan = Mutex<Bool?>(nil)
    let settings = settings
    let recorded = await TipLedger.record(.verified(transaction), in: settings) {
      flagWhenCallbackRan.withLock { $0 = settings.hasTipped }
      transaction.noteCallbackRan()
    }
    #expect(recorded == true)
    #expect(flagWhenCallbackRan.withLock { $0 } == true)
    #expect(transaction.callbackRanBeforeFinish == true)
    #expect(transaction.finishCount == 1)
  }

  @Test func anUnverifiedOrUnknownTipNeverRunsTheCallback() async {
    let unverified = fake(TipTier.coffee.productID)
    let unknown = fake("app.vitalcourier.other")
    let callbackCount = Mutex(0)

    _ = await TipLedger.record(.unverified(unverified), in: settings) { callbackCount.withLock { $0 += 1 } }
    _ = await TipLedger.record(.verified(unknown), in: settings) { callbackCount.withLock { $0 += 1 } }

    #expect(callbackCount.withLock { $0 } == 0)
    #expect(unverified.finishCount == 0)
    #expect(unknown.finishCount == 0)
  }

  @Test func anUnverifiedTipIsNeitherCountedNorFinished() async {
    let transaction = fake(TipTier.coffee.productID)
    let recorded = await TipLedger.record(.unverified(transaction), in: settings) {}
    #expect(recorded == false)
    #expect(settings.hasTipped == false)
    #expect(transaction.finishCount == 0)
  }

  @Test func anUnknownProductIsLeftAlone() async {
    let transaction = fake("app.vitalcourier.other")
    let recorded = await TipLedger.record(.verified(transaction), in: settings) {}
    #expect(recorded == false)
    #expect(settings.hasTipped == false)
    #expect(transaction.finishCount == 0)
  }

  @Test func aVerifiedPurchaseResultIsThanked() async {
    let transaction = fake(TipTier.coffee.productID)
    let outcome = await TipLedger.outcome(of: .success(.verified(transaction)), in: settings) {}
    #expect(outcome == .thanked)
    #expect(settings.hasTipped)
    #expect(transaction.finishCount == 1)
  }

  @Test func anUnverifiedPurchaseResultFails() async {
    let transaction = fake(TipTier.coffee.productID)
    let outcome = await TipLedger.outcome(of: .success(.unverified(transaction)), in: settings) {}
    #expect(outcome == .failed)
    #expect(settings.hasTipped == false)
    #expect(transaction.finishCount == 0)
  }

  @Test func aCancelledPurchaseIsNeitherCountedNorFinished() async {
    let outcome = await TipLedger.outcome(of: TipPurchaseResult<FakeTipTransaction>.userCancelled, in: settings) {}
    #expect(outcome == .cancelled)
    #expect(settings.hasTipped == false)
  }

  @Test func aPendingPurchaseIsNotCounted() async {
    let outcome = await TipLedger.outcome(of: TipPurchaseResult<FakeTipTransaction>.pending, in: settings) {}
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

  @Test func historyWithAVerifiedTipSetsTheFlagWithoutFinishing() async {
    let transaction = fake(TipTier.coffee.productID)
    let found = await TipLedger.recordFromHistory(stream([.verified(transaction)]), in: settings)
    #expect(found == true)
    #expect(settings.hasTipped)
    #expect(transaction.finishCount == 0)
  }

  @Test func historySkipsUnverifiedRevokedAndUnknownTransactions() async {
    let unverified = fake(TipTier.coffee.productID)
    let revoked = fake(TipTier.coffee.productID, isRevoked: true)
    let unknown = fake("app.vitalcourier.other")
    let found = await TipLedger.recordFromHistory(
      stream([.unverified(unverified), .verified(revoked), .verified(unknown)]), in: settings)
    #expect(found == false)
    #expect(settings.hasTipped == false)
    #expect(unverified.finishCount == 0)
    #expect(revoked.finishCount == 0)
    #expect(unknown.finishCount == 0)
  }

  @Test func historyFindsATipAfterARevokedOne() async {
    let found = await TipLedger.recordFromHistory(
      stream([
        .verified(fake(TipTier.coffee.productID, isRevoked: true)),
        .verified(fake(TipTier.coffee.productID)),
      ]), in: settings)
    #expect(found == true)
    #expect(settings.hasTipped)
  }

  @Test func emptyHistoryFindsNothing() async {
    let found = await TipLedger.recordFromHistory(stream([]), in: settings)
    #expect(found == false)
    #expect(settings.hasTipped == false)
  }

  @Test func historyDoesNothingOnceTipped() async {
    settings.hasTipped = true
    let transaction = fake(TipTier.coffee.productID)
    let found = await TipLedger.recordFromHistory(stream([.verified(transaction)]), in: settings)
    #expect(found == false)
    #expect(settings.hasTipped == true)
    #expect(transaction.finishCount == 0)
  }

  @Test func aRevokedTransactionIsFinishedWithoutTheFlagOrTheCallback() async {
    let transaction = fake(TipTier.coffee.productID, isRevoked: true)
    let callbackRan = Mutex(false)
    let recorded = await TipLedger.record(.verified(transaction), in: settings) {
      callbackRan.withLock { $0 = true }
    }
    #expect(recorded == false)
    #expect(settings.hasTipped == false)
    #expect(transaction.finishCount == 1)
    #expect(callbackRan.withLock { $0 } == false)
  }

  @Test func aRevokedTransactionNeverClearsTheFlag() async {
    settings.hasTipped = true
    let transaction = fake(TipTier.coffee.productID, isRevoked: true)
    let recorded = await TipLedger.record(.verified(transaction), in: settings) {}
    #expect(recorded == false)
    #expect(settings.hasTipped == true)
    #expect(transaction.finishCount == 1)
  }

  @Test func anUnfinishedTipIsRecordedAndFinishedBeforeHistory() async {
    let unfinishedTip = fake(TipTier.coffee.productID)
    let historyTip = fake(TipTier.smallThanks.productID)
    let recordedCount = Mutex(0)
    let found = await TipLedger.recordUnfinishedThenHistory(
      unfinished: stream([.verified(unfinishedTip)]),
      history: stream([.verified(historyTip)]),
      in: settings
    ) { recordedCount.withLock { $0 += 1 } }
    #expect(found == true)
    #expect(unfinishedTip.finishCount == 1)
    #expect(historyTip.finishCount == 0)
    #expect(recordedCount.withLock { $0 } == 1)
  }

  @Test func historyIsTheFallbackWhenNothingIsUnfinished() async {
    let historyTip = fake(TipTier.coffee.productID)
    let recordedCount = Mutex(0)
    let found = await TipLedger.recordUnfinishedThenHistory(
      unfinished: stream([]),
      history: stream([.verified(historyTip)]),
      in: settings
    ) { recordedCount.withLock { $0 += 1 } }
    #expect(found == true)
    #expect(settings.hasTipped)
    #expect(historyTip.finishCount == 0)
    #expect(recordedCount.withLock { $0 } == 1)
  }

  @Test func historyIsReadOnlyAfterUnfinishedIsDrained() async {
    let log = Mutex<[String]>([])
    let revokedUnfinished = FakeTipTransaction(
      productID: TipTier.coffee.productID, settings: settings, isRevoked: true,
      onFinish: { log.withLock { $0.append("finished") } })
    let historyTip = fake(TipTier.coffee.productID)
    let pulls = Mutex(0)
    let history = AsyncStream<TipVerification<FakeTipTransaction>>(unfolding: {
      let pull = pulls.withLock { count in
        count += 1
        return count
      }
      guard pull == 1 else { return nil }
      log.withLock { $0.append("history read") }
      return .verified(historyTip)
    })
    let found = await TipLedger.recordUnfinishedThenHistory(
      unfinished: stream([.verified(revokedUnfinished)]), history: history, in: settings
    ) {}
    #expect(found == true)
    #expect(log.withLock { $0 } == ["finished", "history read"])
  }

  @Test func nothingAnywhereRecordsNothing() async {
    let recordedCount = Mutex(0)
    let found = await TipLedger.recordUnfinishedThenHistory(
      unfinished: stream([]), history: stream([]), in: settings
    ) { recordedCount.withLock { $0 += 1 } }
    #expect(found == false)
    #expect(recordedCount.withLock { $0 } == 0)
  }
}
