import Foundation

/// The tip jar's decisions, free of StoreKit so they can be tested without it. The app layer maps StoreKit's types onto these.

/// The three tips, in display order.
public enum TipTier: String, CaseIterable, Sendable {
    case smallThanks = "app.vitalcourier.tip.small"
    case coffee = "app.vitalcourier.tip.coffee"
    case keepGoing = "app.vitalcourier.tip.keepgoing"

    public var productID: String { rawValue }
}

public enum TipPurchaseOutcome: Equatable, Sendable {
    case thanked, cancelled, failed, pending
}

/// A StoreKit transaction, reduced to what the ledger needs.
public protocol TipTransaction: Sendable {
    var productID: String { get }
    func finish() async
}

public enum TipVerification<Transaction: TipTransaction>: Sendable {
    case verified(Transaction)
    case unverified(Transaction)
}

/// The StoreKit-free shape of a purchase result.
public enum TipPurchaseResult<Transaction: TipTransaction>: Sendable {
    case success(TipVerification<Transaction>)
    case userCancelled
    case pending
}

public enum TipLedger: Sendable {
    /// Saves the flag before finishing, so a crash in between replays the transaction instead of losing the thanks. An unverified or unknown transaction is never finished, which leaves StoreKit free to redeliver it.
    public static func record<Transaction: TipTransaction>(
        _ verification: TipVerification<Transaction>,
        in settings: AppSettings
    ) async -> Bool {
        guard case .verified(let transaction) = verification,
              TipTier(rawValue: transaction.productID) != nil else { return false }
        settings.hasTipped = true
        await transaction.finish()
        return true
    }

    public static func outcome<Transaction: TipTransaction>(
        of result: TipPurchaseResult<Transaction>,
        in settings: AppSettings
    ) async -> TipPurchaseOutcome {
        switch result {
        case .success(let verification):
            return await record(verification, in: settings) ? .thanked : .failed
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        }
    }

    /// Holds the per-sequence logic of the transaction listener's loops. `Failure == Never` makes "must not throw" a compile-time rule: `Transaction.updates`, `Transaction.unfinished` and `AsyncStream` don't throw.
    public static func recordEach<Verifications: AsyncSequence, Transaction: TipTransaction>(
        _ verifications: Verifications,
        in settings: AppSettings,
        onRecorded: @Sendable () async -> Void
    ) async where Verifications.Element == TipVerification<Transaction>, Verifications.Failure == Never {
        for await verification in verifications where await record(verification, in: settings) {
            await onRecorded()
        }
    }
}

public struct TipJarState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading, unavailable, ready, purchasing(TipTier), thanked
    }

    public private(set) var phase: Phase
    /// A purchase is waiting for approval (Ask to Buy). The line stays while the buyer tries again.
    public private(set) var isAwaitingApproval: Bool
    public private(set) var showsFailure: Bool

    public static func initial(hasTipped: Bool) -> TipJarState {
        TipJarState(phase: hasTipped ? .thanked : .loading, isAwaitingApproval: false, showsFailure: false)
    }

    public var needsProducts: Bool { phase == .loading }

    public mutating func productsLoaded(availableTiers: Set<TipTier>) {
        guard phase == .loading else { return }
        phase = availableTiers.isSuperset(of: TipTier.allCases) ? .ready : .unavailable
    }

    public mutating func productsFailedToLoad() {
        guard phase == .loading else { return }
        phase = .unavailable
    }

    /// Returns whether a purchase should start; a tap in any phase but `.ready` is ignored.
    public mutating func purchaseStarted(_ tier: TipTier) -> Bool {
        guard phase == .ready else { return false }
        phase = .purchasing(tier)
        showsFailure = false
        return true
    }

    public mutating func purchaseEnded(_ outcome: TipPurchaseOutcome) {
        guard case .purchasing = phase else { return }
        switch outcome {
        case .thanked:
            becomeThanked()
        case .cancelled:
            phase = .ready
        case .failed:
            phase = .ready
            showsFailure = true
        case .pending:
            phase = .ready
            isAwaitingApproval = true
        }
    }

    /// The transaction listener recorded a tip (a restored or approved one), whatever the screen was doing.
    public mutating func tipRecordedElsewhere() {
        becomeThanked()
    }

    public mutating func sectionReappeared() {
        showsFailure = false
    }

    private mutating func becomeThanked() {
        phase = .thanked
        isAwaitingApproval = false
        showsFailure = false
    }
}
