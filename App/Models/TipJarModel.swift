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

  init(settings: AppSettings) {
    self.settings = settings
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

  func loadIfNeeded() async {
    showThanksIfTipWasRecorded()
    guard state.needsProducts else { return }
    do {
      let products = try await Product.products(for: TipTier.allCases.map(\.productID))
      // A cancelled load can still return normally; stay in Loading so the next visit retries.
      guard !Task.isCancelled else { return }
      for product in products {
        guard let tier = TipTier(rawValue: product.id) else { continue }
        productsByTier[tier] = product
        pricesByTier[tier] = product.displayPrice
      }
      state.productsLoaded(availableTiers: Set(productsByTier.keys))
    } catch {
      // Leaving Settings cancels the load; that is not a failure, so the next visit retries.
      guard !Task.isCancelled else { return }
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

  /// Runs between saving the flag and finishing the transaction, so a slow `finish()` can't leave a paid buyer on Purchasing.
  private func showThanksBeforeFinishing() {
    state.tipRecordedElsewhere()
  }

  func sectionAppeared() {
    showThanksIfTipWasRecorded()
    state.sectionReappeared()
  }
}
