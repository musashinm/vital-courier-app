import Foundation
import StoreKit
import StoreKitTest
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite(.serialized) @MainActor struct TipJarModelTests {
  // `xcodebuild test` doesn't sync the StoreKit configuration into a fresh simulator, so a purchase
  // hits the real App Store and waits on a "Sign in to Apple Account" alert. CI sets this to skip them.
  nonisolated static let skipsStoreKitPurchases =
    ProcessInfo.processInfo.environment["SKIP_STOREKIT_PURCHASE_TESTS"] == "1"

  private final class BundleAnchor {}

  private func makeSession() throws -> SKTestSession {
    let session: SKTestSession
    do {
      session = try SKTestSession(configurationFileNamed: "TipJar")
    } catch {
      let configurationURL = try #require(
        Bundle(for: BundleAnchor.self).url(forResource: "TipJar", withExtension: "storekit"))
      session = try SKTestSession(contentsOf: configurationURL)
    }
    session.disableDialogs = true
    session.clearTransactions()
    return session
  }

  @Test func loadsAllThreeTiersWithStorePrices() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.clearTransactions()
      settings.hasTipped = false
    }
    let model = TipJarModel(settings: settings)

    await model.loadIfNeeded()

    #expect(model.state.phase == .ready)
    #expect(model.pricesByTier[.smallThanks] == "$1.99")
    #expect(model.pricesByTier[.coffee] == "$4.99")
    #expect(model.pricesByTier[.keepGoing] == "$9.99")
  }

  @Test(
    .disabled(
      if: Self.skipsStoreKitPurchases, "StoreKit purchases need a simulator Xcode has synced the configuration into"))
  func aSuccessfulTipSavesTheFlagAndThanks() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.clearTransactions()
      settings.hasTipped = false
    }
    let model = TipJarModel(settings: settings)
    await model.loadIfNeeded()

    await model.purchase(.coffee)

    #expect(settings.hasTipped)
    #expect(model.state.phase == .thanked)
    // Under load StoreKitTest can ignore a finish() that follows the purchase closely, so TipLedgerTests checks finishing with a fake transaction instead.
  }

  @Test(
    .disabled(
      if: Self.skipsStoreKitPurchases, "StoreKit purchases need a simulator Xcode has synced the configuration into"))
  func aFailedPurchaseLeavesTheRowsWithTheFailureLine() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.resetToDefaultState()
      session.clearTransactions()
      settings.hasTipped = false
    }
    try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
    let model = TipJarModel(settings: settings)
    await model.loadIfNeeded()

    await model.purchase(.smallThanks)

    #expect(model.state.phase == .ready)
    #expect(model.state.showsFailure)
    #expect(settings.hasTipped == false)
  }

  @Test(
    .disabled(
      if: Self.skipsStoreKitPurchases, "StoreKit purchases need a simulator Xcode has synced the configuration into"))
  func anApprovedAskToBuyTipThanksThroughTheListener() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.resetToDefaultState()
      session.clearTransactions()
      settings.hasTipped = false
    }
    session.askToBuyEnabled = true
    let model = TipJarModel(settings: settings)
    await model.loadIfNeeded()

    await model.purchase(.keepGoing)

    #expect(model.state.phase == .ready)
    #expect(model.state.isAwaitingApproval)
    #expect(settings.hasTipped == false)

    let pendingTransaction = try #require(session.allTransactions().first)
    try session.approveAskToBuyTransaction(identifier: pendingTransaction.identifier)
    let approvalDeadline = ContinuousClock.now + .seconds(10)
    // The listener saves the flag, then posts a notification that reaches the model through the main actor, so wait for the phase too.
    while !(settings.hasTipped && model.state.phase == .thanked) && ContinuousClock.now < approvalDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }

    #expect(settings.hasTipped)
    #expect(model.state.phase == .thanked)
  }

  @Test func aRelaunchAfterATipShowsThanksWithoutLoading() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = true
    defer {
      session.clearTransactions()
      settings.hasTipped = false
    }
    let model = TipJarModel(settings: settings)

    #expect(model.state.phase == .thanked)
    await model.loadIfNeeded()

    #expect(model.state.phase == .thanked)
    #expect(model.pricesByTier.isEmpty)
  }
}
