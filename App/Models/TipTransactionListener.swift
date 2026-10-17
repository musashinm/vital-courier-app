import Foundation
import StoreKit
import VitalCourierCore

/// `StoreKit.Transaction` reduced to what `TipLedger` needs.
struct StoreKitTipTransaction: TipTransaction {
    let transaction: StoreKit.Transaction

    var productID: String { transaction.productID }

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

/// Records tips that arrive outside a purchase on screen: an approved Ask to Buy, a purchase made on another device, or one an earlier launch never finished.
enum TipTransactionListener {
    /// Started on every launch from the app delegate. One task runs both consumers, so cancelling it stops both.
    @discardableResult
    static func start(settings: AppSettings) -> Task<Void, Never> {
        Task {
            await withTaskGroup(of: Void.self) { group in
                // Updates first, so it very likely subscribes before the sweep. A transaction landing in between stays unfinished and is recorded next launch.
                group.addTask {
                    await TipLedger.recordEach(Transaction.updates.map { TipVerification($0) }, in: settings, onRecorded: Self.announceRecordedTip)
                }
                group.addTask {
                    await TipLedger.recordEach(Transaction.unfinished.map { TipVerification($0) }, in: settings, onRecorded: Self.announceRecordedTip)
                }
            }
        }
    }

    private static func announceRecordedTip() async {
        await MainActor.run { NotificationCenter.default.post(name: .vitalCourierTipRecorded, object: nil) }
    }
}
