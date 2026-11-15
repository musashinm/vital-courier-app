import Foundation
import Observation
import StoreKit
import VitalCourierCore

@MainActor @Observable
final class TipJarModel {
  private(set) var state: TipJarState
  private(set) var pricesByTier: [TipTier: String] = [:]
  private var productsByTier: [TipTier: Product] = [:]
  private let settings: AppSettings
  /// AppStore.sync() in the app; tests pass their own so no sign-in prompt is needed.
  private let syncWithAppStore: @Sendable () async throws -> Void

  init(
    settings: AppSettings,
    syncWithAppStore: @escaping @Sendable () async throws -> Void = { try await AppStore.sync() }
  ) {
    self.settings = settings
    self.syncWithAppStore = syncWithAppStore
    state = .initial(hasTipped: settings.hasTipped)
    // The weak capture keeps this task from retaining the model; the task ends at the next notification after the model is gone.
    Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(named: .vitalCourierTipRecorded) {
        guard let self else { return }
        showThanksIfTipWasRecorded()
      }
    }
  }

  /// The notification observer starts asynchronously and can miss a tip the launch listener recorded first, so the saved flag is the source of truth.
  private func showThanksIfTipWasRecorded() {
    guard settings.hasTipped, state.phase != .thanked else { return }
    state.tipRecordedElsewhere()
  }

  /// The launch preload and the Settings visit share one load: a second caller awaits it instead of starting another.
  private var loadTask: Task<Void, Never>?

  func loadIfNeeded() async {
    showThanksIfTipWasRecorded()
    guard state.needsProducts else { return }
    if let loadTask {
      await loadTask.value
      return
    }
    // Unstructured on purpose: leaving Settings cancels the caller's task, and that must not cancel the load or leave the state in Loading.
    let task = Task { [self] in
      await loadProducts()
      loadTask = nil
    }
    loadTask = task
    await task.value
  }

  private func loadProducts() async {
    do {
      let products = try await Product.products(for: TipTier.allCases.map(\.productID))
      // Each response replaces the stored products, so readiness and prices never mix two partial responses.
      var loadedProducts: [TipTier: Product] = [:]
      var loadedPrices: [TipTier: String] = [:]
      for product in products {
        guard let tier = TipTier(rawValue: product.id) else { continue }
        loadedProducts[tier] = product
        loadedPrices[tier] = product.displayPrice
      }
      productsByTier = loadedProducts
      pricesByTier = loadedPrices
      state.productsLoaded(availableTiers: Set(loadedProducts.keys))
    } catch {
      state.productsFailedToLoad()
    }
  }

  func purchase(_ tier: TipTier) async {
    guard state.purchaseStarted(tier) else { return }
    guard let product = productsByTier[tier] else {
      state.purchaseEnded(.failed)
      return
    }
    let outcome: TipPurchaseOutcome
    do {
      switch try await product.purchase() {
      case .success(let result):
        outcome = await TipLedger.outcome(
          of: TipPurchaseResult.success(TipVerification(result)), in: settings, afterSaving: showThanksBeforeFinishing)
      case .userCancelled:
        outcome = await TipLedger.outcome(
          of: TipPurchaseResult<StoreKitTipTransaction>.userCancelled, in: settings,
          afterSaving: showThanksBeforeFinishing)
      case .pending:
        outcome = await TipLedger.outcome(
          of: TipPurchaseResult<StoreKitTipTransaction>.pending, in: settings, afterSaving: showThanksBeforeFinishing)
      @unknown default:
        outcome = .failed
      }
    } catch {
      outcome = .failed
    }
    state.purchaseEnded(outcome)
  }

  /// The Restore button. sync() asks for the Apple Account, so it only ever runs from a tap. History is checked even when sync() throws, since StoreKit may already hold the tip.
  func restore() async {
    // The same order as the launch check: a sync can surface a tip that is still unfinished, and it must be finished, not just flagged.
    await restore(
      unfinished: Transaction.unfinished.map { TipVerification($0) },
      history: Transaction.all.map { TipVerification($0) })
  }

  /// Takes the transaction sources as parameters so a test can drive restore without StoreKit.
  func restore<
    Unfinished: AsyncSequence, History: AsyncSequence, RestoredTransaction: TipTransaction
  >(unfinished: sending Unfinished, history: sending History) async
  where
    Unfinished.Element == TipVerification<RestoredTransaction>, Unfinished.Failure == Never,
    History.Element == TipVerification<RestoredTransaction>, History.Failure == Never
  {
    guard state.restoreStarted() else { return }
    var syncError: (any Error)?
    do {
      try await syncWithAppStore()
    } catch {
      syncError = error
    }
    // Thanked as soon as the flag is saved, before finish(): a slow finish() must not keep a restored tip on Restoring. The later restoreEnded is a no-op from Thanked.
    let found = await TipLedger.recordUnfinishedThenHistory(
      unfinished: unfinished, history: history, in: settings, onRecorded: showThanksBeforeFinishing)
    state.restoreEnded(Self.restoreOutcome(found: found || settings.hasTipped, syncError: syncError))
  }

  private static func restoreOutcome(found: Bool, syncError: (any Error)?) -> TipRestoreOutcome {
    if found { return .restored }
    guard let syncError else { return .nothingFound }
    if let storeError = syncError as? StoreKitError, case .userCancelled = storeError { return .cancelled }
    return .failed
  }

  /// Runs between saving the flag and finishing the transaction, so a slow `finish()` can't leave a paid buyer on Purchasing.
  private func showThanksBeforeFinishing() {
    state.tipRecordedElsewhere()
  }

  func sectionAppeared() {
    showThanksIfTipWasRecorded()
    state.sectionReappeared()
  }
}
