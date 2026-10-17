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
}
