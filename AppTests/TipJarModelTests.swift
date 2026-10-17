import Foundation
import StoreKit
import StoreKitTest
import Testing
import VitalCourierCore
@testable import VitalCourier

@Suite(.serialized) @MainActor struct TipJarModelTests {
    private final class BundleAnchor {}

    private func makeSession() throws -> SKTestSession {
        let configurationURL = try #require(Bundle(for: BundleAnchor.self).url(forResource: "TipJar", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func loadsAllThreeTiersWithStorePrices() async throws {
        let session = try makeSession()
        let settings = AppEnvironment.shared.settings
        settings.hasTipped = false
        defer { session.clearTransactions(); settings.hasTipped = false }
        let model = TipJarModel(settings: settings)

        await model.loadIfNeeded()

        #expect(model.state.phase == .ready)
        #expect(model.pricesByTier[.smallThanks] == "$1.99")
        #expect(model.pricesByTier[.coffee] == "$4.99")
        #expect(model.pricesByTier[.keepGoing] == "$9.99")
    }

    @Test func aSuccessfulTipSavesTheFlagThanksAndFinishes() async throws {
        let session = try makeSession()
        let settings = AppEnvironment.shared.settings
        settings.hasTipped = false
        defer { session.clearTransactions(); settings.hasTipped = false }
        let model = TipJarModel(settings: settings)
        await model.loadIfNeeded()

        await model.purchase(.coffee)

        #expect(settings.hasTipped)
        #expect(model.state.phase == .thanked)
        var unfinishedCoffeeCount = 0
        for await verification in Transaction.unfinished {
            if case .verified(let transaction) = verification, transaction.productID == TipTier.coffee.productID {
                unfinishedCoffeeCount += 1
            }
        }
        #expect(unfinishedCoffeeCount == 0)
    }

    @Test func aFailedPurchaseLeavesTheRowsWithTheFailureLine() async throws {
        let session = try makeSession()
        let settings = AppEnvironment.shared.settings
        settings.hasTipped = false
        defer { session.resetToDefaultState(); session.clearTransactions(); settings.hasTipped = false }
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        let model = TipJarModel(settings: settings)
        await model.loadIfNeeded()

        await model.purchase(.smallThanks)

        #expect(model.state.phase == .ready)
        #expect(model.state.showsFailure)
        #expect(settings.hasTipped == false)
    }

    @Test func anApprovedAskToBuyTipThanksThroughTheListener() async throws {
        let session = try makeSession()
        let settings = AppEnvironment.shared.settings
        settings.hasTipped = false
        defer { session.resetToDefaultState(); session.clearTransactions(); settings.hasTipped = false }
        session.askToBuyEnabled = true
        let model = TipJarModel(settings: settings)
        await model.loadIfNeeded()

        await model.purchase(.keepGoing)

        #expect(model.state.phase == .ready)
        #expect(model.state.isAwaitingApproval)
        #expect(settings.hasTipped == false)

        let pendingTransaction = try #require(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pendingTransaction.identifier)
        let deadline = ContinuousClock.now + .seconds(5)
        while !settings.hasTipped && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // The notification hops through the main actor; give the model's observer a turn.
        try await Task.sleep(for: .milliseconds(100))

        #expect(settings.hasTipped)
        #expect(model.state.phase == .thanked)
    }

    @Test func aRelaunchAfterATipShowsThanksWithoutLoading() async throws {
        let session = try makeSession()
        let settings = AppEnvironment.shared.settings
        settings.hasTipped = true
        defer { session.clearTransactions(); settings.hasTipped = false }
        let model = TipJarModel(settings: settings)

        #expect(model.state.phase == .thanked)
        await model.loadIfNeeded()

        #expect(model.state.phase == .thanked)
        #expect(model.pricesByTier.isEmpty)
    }
}
