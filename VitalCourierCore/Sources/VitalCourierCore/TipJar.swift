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

public enum TipRestoreOutcome: Equatable, Sendable {
  case restored, nothingFound, cancelled, failed
}

/// A StoreKit transaction, reduced to what the ledger needs.
public protocol TipTransaction: Sendable {
  var productID: String { get }
  /// Refunded or revoked by Apple (StoreKit's revocationDate is set).
  var isRevoked: Bool { get }
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
  /// Saves the flag, runs `afterSaving`, then finishes, so a crash in between replays the transaction instead of losing the thanks, and a slow `finish()` never keeps a paid buyer waiting. An unverified or unknown transaction is never finished and never calls `afterSaving`, which leaves StoreKit free to redeliver it. A revoked transaction is finished without saving the flag.
  public static func record<Transaction: TipTransaction>(
    _ verification: TipVerification<Transaction>,
    in settings: AppSettings,
    afterSaving: @Sendable () async -> Void
  ) async -> Bool {
    guard case .verified(let transaction) = verification,
      TipTier(rawValue: transaction.productID) != nil
    else { return false }
    // A refund arrives through Transaction.updates too: finish it so it isn't redelivered, but it never thanks and never clears an earlier thanks.
    if transaction.isRevoked {
      await transaction.finish()
      return false
    }
    settings.hasTipped = true
    await afterSaving()
    await transaction.finish()
    return true
  }

  public static func outcome<Transaction: TipTransaction>(
    of result: TipPurchaseResult<Transaction>,
    in settings: AppSettings,
    afterSaving: @Sendable () async -> Void
  ) async -> TipPurchaseOutcome {
    switch result {
    case .success(let verification):
      return await record(verification, in: settings, afterSaving: afterSaving) ? .thanked : .failed
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
    for await verification in verifications where await record(verification, in: settings, afterSaving: onRecorded) {}
  }

  /// The fallback for finished tips: after a reinstall the saved flag is gone, but with `SKIncludeConsumableInAppPurchaseHistory` set, `Transaction.all` still lists them. Returns whether this call saved the flag. `Transaction.all` lists unfinished tips too, so call this only through `recordUnfinishedThenHistory`, after `unfinished` is drained. It never finishes anything and never clears the flag.
  static func recordFromHistory<Verifications: AsyncSequence, Transaction: TipTransaction>(
    _ verifications: Verifications,
    in settings: AppSettings
  ) async -> Bool where Verifications.Element == TipVerification<Transaction>, Verifications.Failure == Never {
    guard !settings.hasTipped else { return false }
    for await verification in verifications {
      guard case .verified(let transaction) = verification,
        TipTier(rawValue: transaction.productID) != nil,
        !transaction.isRevoked
      else { continue }
      settings.hasTipped = true
      return true
    }
    return false
  }

  /// The launch check and Restore's second look, in the only safe order: unfinished tips are recorded and finished first, and finished history is read only after that. Returns whether either step recorded a tip.
  @discardableResult
  public static func recordUnfinishedThenHistory<
    Unfinished: AsyncSequence, History: AsyncSequence, Transaction: TipTransaction
  >(
    unfinished: Unfinished,
    history: History,
    in settings: AppSettings,
    onRecorded: @Sendable () async -> Void
  ) async -> Bool
  where
    Unfinished.Element == TipVerification<Transaction>, Unfinished.Failure == Never,
    History.Element == TipVerification<Transaction>, History.Failure == Never
  {
    var recorded = false
    for await verification in unfinished where await record(verification, in: settings, afterSaving: onRecorded) {
      recorded = true
    }
    if await recordFromHistory(history, in: settings) {
      await onRecorded()
      recorded = true
    }
    return recorded
  }
}

public struct TipJarState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case loading, unavailable, ready
    case purchasing(TipTier)
    case restoring
    case thanked
  }

  public private(set) var phase: Phase
  /// A purchase is waiting for approval (Ask to Buy). The line stays while the buyer tries again.
  public private(set) var isAwaitingApproval: Bool
  public private(set) var showsFailure: Bool

  public enum RestoreNotice: Equatable, Sendable { case nothingFound, failed }
  /// The line under the Restore button after a restore that found nothing or failed. Cleared like `showsFailure`.
  public private(set) var restoreNotice: RestoreNotice?

  public static func initial(hasTipped: Bool) -> TipJarState {
    TipJarState(phase: hasTipped ? .thanked : .loading, isAwaitingApproval: false, showsFailure: false)
  }

  /// Unavailable is retried on the next visit to Settings, so a transient failure doesn't hide the tips until relaunch.
  public var needsProducts: Bool { phase == .loading || phase == .unavailable }

  /// Settings hides the tip jar entirely when the tips couldn't load, rather than opening on an error line.
  public var showsSection: Bool { phase != .unavailable }

  public mutating func productsLoaded(availableTiers: Set<TipTier>) {
    guard needsProducts else { return }
    phase = availableTiers.isSuperset(of: TipTier.allCases) ? .ready : .unavailable
  }

  public mutating func productsFailedToLoad() {
    guard needsProducts else { return }
    phase = .unavailable
  }

  /// Returns whether a purchase should start; a tap in any phase but `.ready` is ignored.
  public mutating func purchaseStarted(_ tier: TipTier) -> Bool {
    guard phase == .ready else { return false }
    phase = .purchasing(tier)
    showsFailure = false
    restoreNotice = nil
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

  /// Returns whether a restore should start; only Ready can start one.
  public mutating func restoreStarted() -> Bool {
    guard phase == .ready else { return false }
    phase = .restoring
    showsFailure = false
    restoreNotice = nil
    return true
  }

  public mutating func restoreEnded(_ outcome: TipRestoreOutcome) {
    guard phase == .restoring else { return }
    switch outcome {
    case .restored:
      becomeThanked()
    case .nothingFound:
      phase = .ready
      restoreNotice = .nothingFound
    case .cancelled:
      phase = .ready
    case .failed:
      phase = .ready
      restoreNotice = .failed
    }
  }

  /// The transaction listener recorded a tip (a restored or approved one), whatever the screen was doing.
  public mutating func tipRecordedElsewhere() {
    becomeThanked()
  }

  public mutating func sectionReappeared() {
    showsFailure = false
    restoreNotice = nil
  }

  private mutating func becomeThanked() {
    phase = .thanked
    isAwaitingApproval = false
    showsFailure = false
    restoreNotice = nil
  }
}
