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
    @ObservationIgnored private var recordedTipObservation: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        state = .initial(hasTipped: settings.hasTipped)
        recordedTipObservation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .vitalCourierTipRecorded) {
                guard let self else { return }
                state.tipRecordedElsewhere()
            }
        }
    }

    isolated deinit {
        recordedTipObservation?.cancel()
    }

    func loadIfNeeded() async {
        guard state.needsProducts else { return }
        do {
            let products = try await Product.products(for: TipTier.allCases.map(\.productID))
            for product in products {
                guard let tier = TipTier(rawValue: product.id) else { continue }
                productsByTier[tier] = product
                pricesByTier[tier] = product.displayPrice
            }
            state.productsLoaded(availableTiers: Set(productsByTier.keys))
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
                outcome = await TipLedger.outcome(of: TipPurchaseResult.success(TipVerification(result)), in: settings)
            case .userCancelled:
                outcome = await TipLedger.outcome(of: TipPurchaseResult<StoreKitTipTransaction>.userCancelled, in: settings)
            case .pending:
                outcome = await TipLedger.outcome(of: TipPurchaseResult<StoreKitTipTransaction>.pending, in: settings)
            @unknown default:
                outcome = .failed
            }
        } catch {
            outcome = .failed
        }
        state.purchaseEnded(outcome)
    }

    func sectionAppeared() {
        state.sectionReappeared()
    }
}
