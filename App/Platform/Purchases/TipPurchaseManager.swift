import Foundation
import StoreKit
import Observation

/// Ports the Apple/StoreKit rail of `TipService`/`IAPService.buyConsumable`
/// (`ai` branch) onto StoreKit 2 consumables.
///
/// The tip is one backend `Offering`'s consumable product. The order is written
/// to disk (`PendingTipOrder`) BEFORE the store is asked for the money and
/// removed only once the backend accepted the receipt — so a payment StoreKit
/// hands back after the app was killed, or while offline, still finds its
/// order. The backend prices the order from the offering id alone.
///
/// Kept separate from `StoreKitPurchaseManager` (subscription-specific). Its
/// own `Transaction.updates` listener only acts on tip products
/// (`TipProducts.isTipProduct`) and finishes a failed tip transaction so
/// StoreKit stops redelivering it.
@MainActor
@Observable
final class TipPurchaseManager {
    enum Status: Equatable, Sendable {
        case idle
        case purchasing
        case completed
    }

    enum TipPurchaseError: Error, Equatable, Sendable {
        /// The backend order came back without an id: charging for an order
        /// nothing can be verified against would leave an orphan payment.
        case orderUnavailable
        /// `IAPService.buyConsumable`'s `!available` branch.
        case iapUnavailable
        /// `IAPService.buyConsumable`'s `response.productDetails.isEmpty`
        /// branch.
        case productUnavailable
        /// StoreKit rejected the transaction's own signature — no Dart
        /// equivalent, same new-to-StoreKit-2 failure mode
        /// `StoreKitPurchaseManager.PurchaseError.failedVerification` notes.
        case failedVerification

        var displayMessage: String {
            switch self {
            case .orderUnavailable:
                String(localized: "Couldn't start your tip")
            case .iapUnavailable:
                String(localized: "In app purchase service is not available on your device please use another option for payment")
            case .productUnavailable:
                String(localized: "This tip option isn't available right now. Please try again later.")
            case .failedVerification:
                String(localized: "This purchase could not be verified by the App Store. Please try again.")
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var lastBackgroundError: (any Error)?

    private let tipRepository: any TipRepository
    private let logger = AppLogger(category: .tips)

    private let pendingStore: any PendingTipOrderStore
    /// The tip started in this process (`TipService._order`).
    private var liveOrder: PendingTipOrder?
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init(tipRepository: any TipRepository, pendingStore: any PendingTipOrderStore) {
        self.tipRepository = tipRepository
        self.pendingStore = pendingStore

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// `TipService.sendTip` end to end: create the backend order → save it →
    /// StoreKit purchase → verify. Returns `true` only once the backend has
    /// verified the transaction; `false` covers cancellation and a pending
    /// (Ask to Buy) purchase, which StoreKit delivers later.
    @discardableResult
    func sendTip(offering: Offering, note: String, creatorId: String?, songId: String?) async throws -> Bool {
        guard status != .purchasing else { return false }
        status = .purchasing
        defer { if status == .purchasing { status = .idle } }

        let order = try await tipRepository.createTipOrder(offering: offering, note: note, creatorId: creatorId, songId: songId)
        guard !order.orderId.isEmpty else { throw TipPurchaseError.orderUnavailable }
        // The backend's product is the one it priced; the offering's is a fallback.
        let productID = order.productId.flatMap { $0.isEmpty ? nil : $0 } ?? offering.productID

        guard AppStore.canMakePayments else {
            throw TipPurchaseError.iapUnavailable
        }
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw TipPurchaseError.productUnavailable
        }

        // Saved first, then the store is asked: a crash in between leaves an
        // unpaid order (harmless), the other way round a payment with no order.
        let pending = PendingTipOrder(orderId: order.orderId, productId: productID)
        liveOrder = pending
        pendingStore.save(pending)

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            // The store refused the payment (`onPurchaseAborted`): no money
            // moved, so the order is dropped.
            abandon()
            throw error
        }

        switch result {
        case let .success(verification):
            // A failure from here on keeps the order on disk: the payment may
            // have gone through, and StoreKit will redeliver the transaction.
            let transaction = try checkVerified(verification)
            try await finalize(transaction: transaction, jws: verification.jwsRepresentation, order: pending)
            status = .completed
            return true
        case .userCancelled:
            abandon()
            return false
        case .pending:
            // Ask to Buy: the approved transaction arrives via `Transaction.updates`.
            return false
        @unknown default:
            abandon()
            return false
        }
    }

    /// The order a purchase of `productID` belongs to: the tip started in this
    /// process, or — for a purchase StoreKit hands back to a fresh process —
    /// the one kept on disk. `nil` when neither was made for that product.
    func pendingOrder(for productID: String) -> PendingTipOrder? {
        if let liveOrder, liveOrder.productId == productID { return liveOrder }
        if let saved = pendingStore.read(), saved.productId == productID { return saved }
        return nil
    }

    /// The always-on listener. Acts only on tip products; a failed tip
    /// transaction is finished so StoreKit stops handing it back.
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        guard TipProducts.isTipProduct(transaction.productID) else { return }
        guard let order = pendingOrder(for: transaction.productID) else {
            logger.warning("tip transaction \(transaction.productID) has no pending order")
            return
        }
        // A foreground purchase is finalized by `sendTip` itself.
        guard status != .purchasing || liveOrder == nil else { return }

        status = .purchasing
        do {
            try await finalize(transaction: transaction, jws: result.jwsRepresentation, order: order)
            status = .completed
        } catch {
            status = .idle
            lastBackgroundError = error
            logger.warning("background tip transaction update failed verification: \(error)")
        }
    }

    private func finalize(transaction: Transaction, jws: String, order: PendingTipOrder) async throws {
        do {
            try await tipRepository.verifyTip(
                orderId: order.orderId,
                receiptData: jws,
                productId: transaction.productID
            )
            await transaction.finish()
            // Only the tip this process started is finished here.
            if liveOrder == order { liveOrder = nil }
            pendingStore.clear()
        } catch {
            // Do NOT finish() — StoreKit redelivers it on the next launch.
            status = .idle
            throw error
        }
    }

    private func abandon() {
        liveOrder = nil
        pendingStore.clear()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipPurchaseError.failedVerification
        case let .verified(safe):
            return safe
        }
    }
}
