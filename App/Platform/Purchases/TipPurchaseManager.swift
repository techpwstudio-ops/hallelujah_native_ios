import Foundation
import StoreKit
import Observation

/// Ports the Apple/StoreKit rail of `TipService`/`IAPService.buyConsumable`
/// (`lib/services/tip_service.dart`, `lib/services/IAPService.dart`) onto
/// real StoreKit 2 consumable purchases.
///
/// Deliberately NOT folded into `StoreKitPurchaseManager`: that type is
/// hard-wired to `SubscriptionRepository`/`SubscriptionPlan`/`Membership`
/// and a subscription's restore-across-launches semantics, none of which
/// apply to a consumable tip — Dart's own `TipService` has no restore
/// method either. A separate, smaller manager avoids genericizing that type
/// away from the shape every one of its other callers depends on.
///
/// `pendingOrderID`/`pendingProductID` are in-memory only, NOT persisted via
/// `KeyValueStoring` the way `StoreKitPurchaseManager`'s pending state is —
/// a faithful difference, not a cut corner: Dart's own
/// `TipService._pending`/`_orderId` are plain in-memory singleton fields
/// too, never written to any local store. The same reasoning covers why
/// there is only ever one pending tip at a time: Dart's `sendTip` guard
/// (`if (_pending) return`) already allows only one in flight app-wide.
///
/// Two purchase-completion paths, same reasoning as
/// `StoreKitPurchaseManager`'s own doc comment: `sendTip(...)` is awaited
/// directly for the common (sandbox) case; the always-on `Transaction
/// .updates` listener (started in `init`) catches the async-resolution edge
/// case (Ask to Buy). Unlike Dart's `IAPService`, which routes every
/// purchase update (subscription AND tip) through ONE shared stream
/// disambiguated by `TipProducts.isTipProduct`, this runs its own
/// independent `Transaction.updates` iteration scoped only to tip product
/// IDs — StoreKit 2 supports multiple concurrent listeners on the same
/// `AsyncSequence`, so this and `StoreKitPurchaseManager`'s own listener
/// never cross-talk; it just means two listeners exist where Dart has one,
/// not that transactions are missed or double-handled.
@MainActor
@Observable
final class TipPurchaseManager {
    enum Status: Equatable, Sendable {
        case idle
        case purchasing
        case completed
    }

    enum TipPurchaseError: Error, Equatable, Sendable {
        /// `TipService._startPurchase`'s `productId == null` guard — this
        /// amount doesn't match any configured tier.
        case invalidAmount
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
            case .invalidAmount:
                "Please choose one of the listed tip amounts."
            case .iapUnavailable:
                "In app purchase service is not available on your device please use another option for payment"
            case .productUnavailable:
                "This tip option isn't available right now. Please try again later."
            case .failedVerification:
                "This purchase could not be verified by the App Store. Please try again."
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var lastBackgroundError: (any Error)?

    private let tipRepository: any TipRepository
    private let logger = AppLogger(category: .tips)

    private var pendingOrderID: String?
    private var pendingProductID: String?
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init(tipRepository: any TipRepository) {
        self.tipRepository = tipRepository

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

    /// `TipService.sendTip` end to end: `createTipOrder` → resolve this
    /// amount's product id → StoreKit purchase → `_verify`. Returns `true`
    /// only once the backend has verified the resulting transaction
    /// (mirrors `IAPService._handlePurchase`'s `onSuccess` branch); `false`
    /// covers user cancellation and a still-pending (Ask to Buy) purchase,
    /// same as Dart's own silent no-op on both.
    @discardableResult
    func sendTip(amount: Int, note: String, creatorId: String?, songId: String?) async throws -> Bool {
        guard status != .purchasing else { return false }
        status = .purchasing
        defer { if status == .purchasing { status = .idle } }

        let order = try await tipRepository.createTipOrder(amount: amount, note: note, creatorId: creatorId, songId: songId)

        guard let productID = TipProducts.productID(forAmount: amount) else {
            throw TipPurchaseError.invalidAmount
        }
        guard AppStore.canMakePayments else {
            throw TipPurchaseError.iapUnavailable
        }
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw TipPurchaseError.productUnavailable
        }
        persist(orderID: order.orderId, productID: productID)

        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            try await finalize(transaction: transaction, jws: verification.jwsRepresentation, orderId: order.orderId)
            status = .completed
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// The always-on listener (started in `init`). Only acts when the
    /// transaction's product matches a locally-pending tip order — same
    /// "nothing locally pending has nothing to verify against" reasoning
    /// `StoreKitPurchaseManager.handleTransactionUpdate` already documents.
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        guard transaction.productID == pendingProductID, let orderID = pendingOrderID else { return }

        status = .purchasing
        do {
            try await finalize(transaction: transaction, jws: result.jwsRepresentation, orderId: orderID)
            status = .completed
        } catch {
            status = .idle
            lastBackgroundError = error
            logger.warning("background tip transaction update failed verification: \(error)")
        }
    }

    private func finalize(transaction: Transaction, jws: String, orderId: String) async throws {
        do {
            try await tipRepository.verifyTip(
                orderId: orderId,
                receiptData: jws,
                productId: transaction.productID
            )
            await transaction.finish()
            clearPendingOrder()
        } catch {
            // Do NOT finish() — same reasoning as
            // `StoreKitPurchaseManager.finalizePurchase`: leaving the
            // transaction unfinished means StoreKit redelivers it via
            // `Transaction.updates` on the next launch/foreground.
            status = .idle
            throw error
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipPurchaseError.failedVerification
        case let .verified(safe):
            return safe
        }
    }

    private func persist(orderID: String, productID: String) {
        pendingOrderID = orderID
        pendingProductID = productID
    }

    private func clearPendingOrder() {
        pendingOrderID = nil
        pendingProductID = nil
    }
}
