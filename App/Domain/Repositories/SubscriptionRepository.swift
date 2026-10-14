/// Ports the Apple/StoreKit rail of `PaymentService`/`IAPService`
/// (`lib/services/payment_service.dart`, `lib/services/IAPService.dart`)
/// against the real `/premium/*` backend contract
/// (`subscriptions.controller.js`, `payment.controller.js`). T61 scope
/// only: Razorpay (`_startExternalPayment`, `RazorpayService`) is T62,
/// family-member management (`getSubscriptionMembers`/invite/remove) is
/// T63, tips (`TipService`) are T64 — none of those have a method here.
///
/// `cancelSubscription` (`GET /premium/subscription/cancel`) is reached
/// only for a web-checkout (Razorpay) subscription — `plans_screen.dart`'s
/// `buildCancelButton` sends APPLE/GOOGLE to the store's own manage page.
/// An account subscribed on another platform can still sign in here, so the
/// Cancel Plan sheets (`showCancelPlanSheet` → `showConfirmCancelSheet`) are
/// ported and end in this call.
protocol SubscriptionRepository: Sendable {
    /// `getPremiumPlans` — the catalogue for this device's platform/country,
    /// already resolved server-side from the `os` header.
    func fetchPlans() async throws -> [SubscriptionPlan]

    /// `PaymentService.createOrder(planId, "APPLE")` — always the Apple
    /// rail on this build (Razorpay/Google are other platforms' concern).
    /// The result's `providerPlanId` is what StoreKit actually buys
    /// against, not the plan's own copy of that field (see
    /// `PaymentOrder`'s doc comment).
    func createPaymentRequest(planId: String) async throws -> PaymentOrder

    /// `PaymentService._verifyCore` — verifies a completed StoreKit
    /// transaction against the order created above. `receiptData` is the
    /// transaction's `jwsRepresentation` (`Transaction.jwsRepresentation`),
    /// matching `_buildPayload`'s APPLE branch
    /// (`{"receiptData": purchase.verificationData.serverVerificationData}`)
    /// verbatim. Returns the refreshed `Membership` on real success, `nil`
    /// on the "already verified" short-circuit (itself still success — the
    /// caller should treat both as "the transaction may be finished").
    func verifyPurchase(orderId: String, receiptData: String) async throws -> Membership?

    /// `PaymentService.cancel` — cancels auto-renew; returns the refreshed
    /// `Membership` (its `subscription` now flagged cancelled).
    func cancelSubscription() async throws -> Membership?
}
