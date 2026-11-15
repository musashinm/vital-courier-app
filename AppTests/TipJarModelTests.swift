import Foundation
import StoreKit
import StoreKitTest
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite(.serialized) @MainActor struct TipJarModelTests {
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

  @Test func aFailedLoadHidesTheSectionAndTheNextVisitRetries() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.resetToDefaultState()
      session.clearTransactions()
      settings.hasTipped = false
    }
    try await session.setSimulatedError(.generic(.unknown), forAPI: .loadProducts)
    let model = TipJarModel(settings: settings)

    await model.loadIfNeeded()

    #expect(model.state.phase == .unavailable)
    #expect(!model.state.showsSection)

    try await session.setSimulatedError(nil, forAPI: .loadProducts)
    await model.loadIfNeeded()

    #expect(model.state.phase == .ready)
    #expect(model.state.showsSection)
  }

  @Test func twoConcurrentLoadsShareOneLoadAndEndReady() async throws {
    let session = try makeSession()
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    defer {
      session.clearTransactions()
      settings.hasTipped = false
    }
    let model = TipJarModel(settings: settings)

    async let launchLoad: Void = model.loadIfNeeded()
    async let settingsLoad: Void = model.loadIfNeeded()
    _ = await (launchLoad, settingsLoad)

    #expect(model.state.phase == .ready)
    #expect(model.pricesByTier.count == TipTier.allCases.count)
  }

  /// A session over the shipped configuration reduced to the given product IDs; StoreKitTest has no call to remove one product.
  /// The caller removes `reducedURL`, the temporary copy the session reads, when the test ends.
  private func makeSession(keepingOnly productIDs: Set<String>) throws -> (session: SKTestSession, reducedURL: URL) {
    let configurationURL = try #require(
      Bundle(for: BundleAnchor.self).url(forResource: "TipJar", withExtension: "storekit")
        ?? Bundle.main.url(forResource: "TipJar", withExtension: "storekit"))
    var configuration = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any])
    let products = try #require(configuration["products"] as? [[String: Any]])
    configuration["products"] = products.filter { productIDs.contains($0["productID"] as? String ?? "") }
    let reducedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TipJar-\(UUID().uuidString).storekit")
    try JSONSerialization.data(withJSONObject: configuration).write(to: reducedURL)
    do {
      let session = try SKTestSession(contentsOf: reducedURL)
      session.disableDialogs = true
      session.clearTransactions()
      return (session, reducedURL)
    } catch {
      try? FileManager.default.removeItem(at: reducedURL)
      throw error
    }
  }

  @Test func twoPartialLoadsThatTogetherHoldEveryTierStayUnavailable() async throws {
    let settings = AppEnvironment.shared.settings
    settings.hasTipped = false
    let first = try makeSession(keepingOnly: [TipTier.smallThanks.rawValue, TipTier.coffee.rawValue])
    defer {
      first.session.resetToDefaultState()
      try? FileManager.default.removeItem(at: first.reducedURL)
      settings.hasTipped = false
    }
    let model = TipJarModel(settings: settings)

    await model.loadIfNeeded()
    #expect(model.state.phase == .unavailable)

    let second = try makeSession(keepingOnly: [TipTier.keepGoing.rawValue])
    defer {
      second.session.resetToDefaultState()
      try? FileManager.default.removeItem(at: second.reducedURL)
    }
    await model.loadIfNeeded()

    #expect(model.state.phase == .unavailable)
    #expect(Set(model.pricesByTier.keys) == [.keepGoing])
  }

  @Test func aSuccessfulTipSavesTheFlagAndThanks() async throws {
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

  @Test func aFailedPurchaseLeavesTheRowsWithTheFailureLine() async throws {
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

  @Test func anApprovedAskToBuyTipThanksThroughTheListener() async throws {
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
