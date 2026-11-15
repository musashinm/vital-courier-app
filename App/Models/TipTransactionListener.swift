import Foundation
import StoreKit
import VitalCourierCore

/// `StoreKit.Transaction` reduced to what `TipLedger` needs.
struct StoreKitTipTransaction: TipTransaction {
  let transaction: StoreKit.Transaction

  var productID: String { transaction.productID }

  var isRevoked: Bool { transaction.revocationDate != nil }

  func finish() async {
    await transaction.finish()
  }
}

extension TipVerification where Transaction == StoreKitTipTransaction {
  init(_ result: VerificationResult<StoreKit.Transaction>) {
    switch result {
    case .verified(let transaction): self = .verified(StoreKitTipTransaction(transaction: transaction))
    case .unverified(let transaction, _): self = .unverified(StoreKitTipTransaction(transaction: transaction))
    }
  }
}

/// Records tips that arrive outside a purchase on screen: an approved Ask to Buy, a purchase made on another device, one an earlier launch never finished, or one bought before a reinstall.
enum TipTransactionListener {
  /// Started on every launch from the app delegate. One task runs the updates consumer and the unfinished-then-history check, so cancelling it stops both.
  @discardableResult
  static func start(settings: AppSettings) -> Task<Void, Never> {
    Task {
      await withTaskGroup(of: Void.self) { group in
        // Updates first, so it very likely subscribes before the sweep. A transaction landing in between stays unfinished and is recorded next launch.
        group.addTask {
          await TipLedger.recordEach(
            Transaction.updates.map { TipVerification($0) }, in: settings, onRecorded: Self.announceRecordedTip)
        }
        // Unfinished first, so every unfinished tip is finished; then finished history, the reinstall fallback (SKIncludeConsumableInAppPurchaseHistory). No sync() here: it prompts for the Apple Account, and Apple says never to call it at launch.
        group.addTask {
          await TipLedger.recordUnfinishedThenHistory(
            unfinished: Transaction.unfinished.map { TipVerification($0) },
            history: Transaction.all.map { TipVerification($0) },
            in: settings, onRecorded: Self.announceRecordedTip)
        }
      }
    }
  }

  private static func announceRecordedTip() async {
    await MainActor.run { NotificationCenter.default.post(name: .vitalCourierTipRecorded, object: nil) }
  }
}
