import Testing

@testable import VitalCourierCore

@Suite struct TipJarStateTests {
  private let allTiers = Set(TipTier.allCases)

  private func readyJar() -> TipJarState {
    var jar = TipJarState.initial(hasTipped: false)
    jar.productsLoaded(availableTiers: allTiers)
    return jar
  }

  private func purchasingJar(_ tier: TipTier = .coffee) -> TipJarState {
    var jar = readyJar()
    _ = jar.purchaseStarted(tier)
    return jar
  }

  @Test func aNewJarLoadsProducts() {
    let jar = TipJarState.initial(hasTipped: false)
    #expect(jar.phase == .loading)
    #expect(jar.needsProducts == true)
  }

  @Test func aThankedJarIgnoresProductLoading() {
    var jar = TipJarState.initial(hasTipped: true)
    #expect(jar.phase == .thanked)
    #expect(jar.needsProducts == false)

    jar.productsLoaded(availableTiers: allTiers)
    #expect(jar.phase == .thanked)
    jar.productsFailedToLoad()
    #expect(jar.phase == .thanked)
  }

  @Test func allThreeTiersMakeTheJarReady() {
    #expect(readyJar().phase == .ready)
  }

  @Test func missingAnyTierMakesTheJarUnavailable() {
    var partial = TipJarState.initial(hasTipped: false)
    partial.productsLoaded(availableTiers: [.smallThanks, .coffee])
    #expect(partial.phase == .unavailable)

    var empty = TipJarState.initial(hasTipped: false)
    empty.productsLoaded(availableTiers: [])
    #expect(empty.phase == .unavailable)

    var failed = TipJarState.initial(hasTipped: false)
    failed.productsFailedToLoad()
    #expect(failed.phase == .unavailable)
  }

  @Test func theSectionShowsInEveryPhaseButUnavailable() {
    #expect(TipJarState.initial(hasTipped: false).showsSection == true)
    #expect(readyJar().showsSection == true)
    #expect(purchasingJar().showsSection == true)
    #expect(TipJarState.initial(hasTipped: true).showsSection == true)

    var failed = TipJarState.initial(hasTipped: false)
    failed.productsFailedToLoad()
    #expect(failed.showsSection == false)

    var partial = TipJarState.initial(hasTipped: false)
    partial.productsLoaded(availableTiers: [.smallThanks, .coffee])
    #expect(partial.showsSection == false)
  }

  @Test func aFailedLoadIsRetriedAndCanBecomeReady() {
    var jar = TipJarState.initial(hasTipped: false)
    jar.productsFailedToLoad()
    #expect(jar.phase == .unavailable)
    #expect(jar.showsSection == false)
    #expect(jar.needsProducts == true)

    jar.productsLoaded(availableTiers: allTiers)
    #expect(jar.phase == .ready)
    #expect(jar.showsSection == true)
  }

  @Test func aSecondFailedLoadStaysUnavailable() {
    var jar = TipJarState.initial(hasTipped: false)
    jar.productsFailedToLoad()
    #expect(jar.phase == .unavailable)
    #expect(jar.needsProducts == true)

    jar.productsFailedToLoad()
    #expect(jar.phase == .unavailable)
    #expect(jar.needsProducts == true)

    jar.productsLoaded(availableTiers: [.coffee])
    #expect(jar.phase == .unavailable)
    #expect(jar.needsProducts == true)
  }

  @Test func aReadyJarDoesNotReload() {
    var jar = readyJar()
    #expect(jar.needsProducts == false)

    jar.productsFailedToLoad()
    #expect(jar.phase == .ready)
  }

  @Test func aSecondTapWhilePurchasingIsIgnored() {
    var jar = readyJar()
    #expect(jar.purchaseStarted(.coffee) == true)
    #expect(jar.phase == .purchasing(.coffee))
    #expect(jar.purchaseStarted(.keepGoing) == false)
    #expect(jar.phase == .purchasing(.coffee))
  }

  @Test func cancelReturnsToReadyQuietly() {
    var jar = purchasingJar()
    jar.purchaseEnded(.cancelled)
    #expect(jar.phase == .ready)
    #expect(jar.showsFailure == false)
  }

  @Test func aFailureShowsTheLineUntilTheNextTapOrReappear() {
    var jar = purchasingJar()
    jar.purchaseEnded(.failed)
    #expect(jar.phase == .ready)
    #expect(jar.showsFailure == true)

    #expect(jar.purchaseStarted(.smallThanks) == true)
    #expect(jar.showsFailure == false)

    jar.purchaseEnded(.failed)
    #expect(jar.showsFailure == true)
    jar.sectionReappeared()
    #expect(jar.showsFailure == false)
  }

  @Test func pendingKeepsTheApprovalLineThroughAnotherPurchase() {
    var jar = purchasingJar()
    jar.purchaseEnded(.pending)
    #expect(jar.phase == .ready)
    #expect(jar.isAwaitingApproval == true)

    _ = jar.purchaseStarted(.coffee)
    jar.purchaseEnded(.cancelled)
    #expect(jar.isAwaitingApproval == true)

    _ = jar.purchaseStarted(.coffee)
    jar.purchaseEnded(.failed)
    #expect(jar.isAwaitingApproval == true)
    #expect(jar.showsFailure == true)
  }

  @Test func aVerifiedTipEndsInThanks() {
    var jar = purchasingJar()
    jar.purchaseEnded(.thanked)
    #expect(jar.phase == .thanked)
    #expect(jar.isAwaitingApproval == false)
    #expect(jar.showsFailure == false)
    #expect(jar.purchaseStarted(.coffee) == false)
  }

  @Test func theListenerCanThankFromAnyPhase() {
    var loading = TipJarState.initial(hasTipped: false)
    loading.tipRecordedElsewhere()

    var awaiting = purchasingJar()
    awaiting.purchaseEnded(.pending)
    awaiting.tipRecordedElsewhere()

    var purchasing = purchasingJar()
    purchasing.tipRecordedElsewhere()

    for jar in [loading, awaiting, purchasing] {
      #expect(jar.phase == .thanked)
      #expect(jar.isAwaitingApproval == false)
      #expect(jar.showsFailure == false)
    }
  }

  @Test func restoreStartsOnlyFromReady() {
    var ready = readyJar()
    #expect(ready.restoreStarted() == true)
    #expect(ready.phase == .restoring)

    var loading = TipJarState.initial(hasTipped: false)
    var thanked = TipJarState.initial(hasTipped: true)
    var purchasing = purchasingJar()
    #expect(loading.restoreStarted() == false)
    #expect(loading.phase == .loading)
    #expect(thanked.restoreStarted() == false)
    #expect(thanked.phase == .thanked)
    #expect(purchasing.restoreStarted() == false)
    #expect(purchasing.phase == .purchasing(.coffee))
  }

  @Test func aRestoredTipThanks() {
    var jar = readyJar()
    _ = jar.restoreStarted()
    jar.restoreEnded(.restored)
    #expect(jar.phase == .thanked)
    #expect(jar.restoreNotice == nil)
  }

  @Test func nothingFoundAndFailedReturnToReadyWithANotice() {
    var nothingFound = readyJar()
    _ = nothingFound.restoreStarted()
    nothingFound.restoreEnded(.nothingFound)
    #expect(nothingFound.phase == .ready)
    #expect(nothingFound.restoreNotice == .nothingFound)

    var failed = readyJar()
    _ = failed.restoreStarted()
    failed.restoreEnded(.failed)
    #expect(failed.phase == .ready)
    #expect(failed.restoreNotice == .failed)
  }

  @Test func aCancelledRestoreReturnsToReadyQuietly() {
    var jar = readyJar()
    _ = jar.restoreStarted()
    jar.restoreEnded(.cancelled)
    #expect(jar.phase == .ready)
    #expect(jar.restoreNotice == nil)
  }

  @Test func theNoticeClearsOnTheNextPurchaseOrVisit() {
    var jar = readyJar()
    _ = jar.restoreStarted()
    jar.restoreEnded(.nothingFound)
    #expect(jar.restoreNotice == .nothingFound)
    _ = jar.purchaseStarted(.coffee)
    #expect(jar.restoreNotice == nil)

    var revisited = readyJar()
    _ = revisited.restoreStarted()
    revisited.restoreEnded(.failed)
    #expect(revisited.restoreNotice == .failed)
    revisited.sectionReappeared()
    #expect(revisited.restoreNotice == nil)
  }

  @Test func aTipRecordedMidRestoreWinsAndTheLateOutcomeIsIgnored() {
    var jar = readyJar()
    _ = jar.restoreStarted()
    jar.tipRecordedElsewhere()
    jar.restoreEnded(.failed)
    #expect(jar.phase == .thanked)
    #expect(jar.restoreNotice == nil)
  }

  @Test func restoreEndedOutsideRestoringIsIgnored() {
    var jar = readyJar()
    jar.restoreEnded(.failed)
    #expect(jar.phase == .ready)
    #expect(jar.restoreNotice == nil)
  }

  @Test func restoringStillHasNoProductsToLoad() {
    var jar = readyJar()
    _ = jar.restoreStarted()
    #expect(jar.needsProducts == false)
    #expect(jar.showsSection == true)
  }
}
