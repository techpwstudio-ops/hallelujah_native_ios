import Foundation
import StoreKit
import Observation

/// Ports the Apple/StoreKit rail of `IAPService`/`PaymentService`
/// (`lib/services/IAPService.dart`, `lib/services/payment_service.dart`)
/// onto real StoreKit 2, not the `in_app_purchase` plugin's StoreKit-1-style
/// callback flow. `@MainActor @Observable`, same shape as
/// `RealtimeConnectionManager` — a captured shared instance wrapping a
/// system framework for the app's whole lifetime.
///
/// Two purchase-completion paths, matching Dart's own two-tier design:
/// `purchase(plan:)`/`restorePurchases()` are awaited directly by the
/// caller for the common (sandbox) case where StoreKit resolves
/// synchronously; the always-on `Transaction.updates` listener (started in
/// `init`) catches the async-resolution edge case (Ask to Buy / parental
/// approval) the same way Dart's always-on `purchaseStream.listen` does —
/// Dart's `_handlePurchase` has no separate code path for that case either,
/// it just relies on the same listener catching the eventual `.purchased`
/// transition whenever it arrives.
///
/// `lastOrderId`/`lastProductId` persist via `KeyValueStoring`, mirroring
/// `PaymentService`'s own `_persist()`/`_loadFromStorage()`/`clear()`
/// (`"last_order_id"`/`"last_provider"`/`"last_product_id"`,
/// `payment_service.dart`) — restore only resumes a locally-persisted
/// PENDING order; it does not reconstruct one from scratch. This is a
/// faithfully-ported LIMITATION, not an oversight: a fresh install that
/// never called `purchase(plan:)` in this session has nothing to verify a
/// restored transaction against, on both Dart and here.
@MainActor
@Observable
final class StoreKitPurchaseManager {
    enum Status: Equatable, Sendable {
        case idle
        case purchasing
        case restoring
        case purchased
    }

    enum PurchaseError: Error, Equatable, Sendable {
        /// `_iap.isAvailable()` returning `false` — Dart's own message:
        /// "In app purchase service is not available on your device please
        /// use another option for payment" (`IAPService.buy`).
        case iapUnavailable
        /// `response.productDetails.isEmpty` — Dart's own message: "There
        /// is issue from developer side, please contact to developer"
        /// (`IAPService.buy`). Also covers this plan having no Apple
        /// mapping at all (`order.providerPlanId == nil`, Dart's
        /// `_productId == null` guard in `_startIAPPurchase`).
        case productUnavailable
        /// StoreKit rejected the transaction's own signature — no Dart
        /// equivalent (the `in_app_purchase` plugin never exposes JWS
        /// verification to the app itself); a genuinely new StoreKit-2-only
        /// failure mode.
        case failedVerification

        var displayMessage: String {
            switch self {
            case .iapUnavailable:
                "In app purchase service is not available on your device please use another option for payment"
            case .productUnavailable:
                "There is issue from developer side, please contact to developer"
            case .failedVerification:
                "This purchase could not be verified by the App Store. Please try again."
            }
        }
    }

    private(set) var status: Status = .idle
    /// Set only by the passive `Transaction.updates` listener, which has no
    /// direct caller to throw to — `purchase(plan:)`/`restorePurchases()`
    /// report failures by throwing instead, matching their `Future<bool>`-
    /// ish direct-await shape in Dart.
    private(set) var lastBackgroundError: (any Error)?

    private let subscriptionRepository: any SubscriptionRepository
    private let membershipStore: MembershipStore
    private let keyValueStore: any KeyValueStoring
    private let logger = AppLogger(category: .subscription)

    private var pendingOrderID: String?
    private var pendingProductID: String?
    private var updatesTask: Task<Void, Never>?

    private static let orderIDKey = "storeKitPendingOrderID"
    private static let productIDKey = "storeKitPendingProductID"

    init(subscriptionRepository: any SubscriptionRepository, membershipStore: MembershipStore, keyValueStore: any KeyValueStoring) {
        self.subscriptionRepository = subscriptionRepository
        self.membershipStore = membershipStore
        self.keyValueStore = keyValueStore
        pendingOrderID = keyValueStore.string(forKey: Self.orderIDKey)
        pendingProductID = keyValueStore.string(forKey: Self.productIDKey)

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

    /// `PaymentService.startIAP` → `createOrder` → `IAPService.buy`
    /// collapsed into one call, since StoreKit 2's `product.purchase()`
    /// (unlike the plugin's `buyNonConsumable`) already returns the actual
    /// outcome directly rather than requiring a separate stream listener
    /// for the common case. Returns `nil` on user cancellation or a
    /// pending (Ask to Buy) purchase, matching Dart's `_handlePurchase`
    /// silently no-op'ing on both (no `case .canceled` toast branch exists
    /// there, and `.pending` only signals loading).
    @discardableResult
    func purchase(plan: SubscriptionPlan) async throws -> Membership? {
        status = .purchasing
        defer { if status == .purchasing { status = .idle } }

        guard AppStore.canMakePayments else {
            throw PurchaseError.iapUnavailable
        }

        let order = try await subscriptionRepository.createPaymentRequest(planId: plan.id)
        guard let productID = order.providerPlanId else {
            throw PurchaseError.productUnavailable
        }
        persist(orderID: order.orderId, productID: productID)

        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PurchaseError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            let membership = try await finalizePurchase(transaction: transaction, orderId: order.orderId)
            status = .purchased
            return membership
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    /// `IAPService.restore()` → `_iap.restorePurchases()`. `AppStore.sync()`
    /// is StoreKit 2's restore-purchases entry point (Apple's own guidance:
    /// call it only in response to an explicit "Restore Purchases" tap,
    /// then read `Transaction.currentEntitlements`) — the closest real
    /// counterpart to the plugin call, not an invented substitute.
    @discardableResult
    func restorePurchases() async throws -> Membership? {
        status = .restoring
        defer { if status == .restoring { status = .idle } }

        try await AppStore.sync()

        guard let orderID = pendingOrderID, let productID = pendingProductID else {
            // Nothing locally remembered to attach a restored transaction
            // to — see this class's doc comment for why that's a faithful
            // port of Dart's own limitation, not a gap.
            return nil
        }

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result), transaction.productID == productID else { continue }
            let membership = try await finalizePurchase(transaction: transaction, orderId: orderID)
            status = .purchased
            return membership
        }
        return nil
    }

    /// The always-on listener (started in `init`, mirroring `IAPService`'s
    /// always-on `purchaseStream.listen`). Only acts when the transaction's
    /// product matches a locally-pending order — a renewal or a transaction
    /// this install never started has no order to verify against here, and
    /// is reconciled server-side via Apple's webhook
    /// (`_handleAppleWebhook`, `payment.service.js`), not by this client;
    /// Dart's own listener never independently re-verifies a transaction it
    /// didn't itself start either.
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        guard transaction.productID == pendingProductID, let orderID = pendingOrderID else { return }

        status = .purchasing
        do {
            _ = try await finalizePurchase(transaction: transaction, orderId: orderID)
            status = .purchased
        } catch {
            status = .idle
            lastBackgroundError = error
            logger.warning("background transaction update failed verification: \(error)")
        }
    }

    private func finalizePurchase(transaction: Transaction, orderId: String) async throws -> Membership? {
        do {
            let membership = try await subscriptionRepository.verifyPurchase(
                orderId: orderId,
                receiptData: transaction.jwsRepresentation
            )
            await transaction.finish()
            if let membership {
                await membershipStore.setMembership(membership)
            }
            clearPendingOrder()
            return membership
        } catch {
            // Do NOT finish() — mirrors Dart: `_handlePurchase` only calls
            // `_completePurchase` when `PaymentService.verifyPurchase`
            // returns `true` (`IAPService.dart`). Leaving the transaction
            // unfinished means StoreKit redelivers it via
            // `Transaction.updates` on next launch/foreground, giving
            // verification another chance instead of silently losing the
            // purchase.
            status = .idle
            throw error
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.failedVerification
        case let .verified(safe):
            return safe
        }
    }

    private func persist(orderID: String, productID: String) {
        pendingOrderID = orderID
        pendingProductID = productID
        keyValueStore.setString(orderID, forKey: Self.orderIDKey)
        keyValueStore.setString(productID, forKey: Self.productIDKey)
    }

    private func clearPendingOrder() {
        pendingOrderID = nil
        pendingProductID = nil
        keyValueStore.setString(nil, forKey: Self.orderIDKey)
        keyValueStore.setString(nil, forKey: Self.productIDKey)
    }
}
