import Foundation

extension Endpoint {
    // MARK: Premium/Subscription (T61) — `subscriptions.controller.js`/
    // `payment.controller.js`, routes confirmed against
    // `subscription.routes.js`/`payment.routes.js`. Apple/StoreKit rail
    // only, matching this task's scope: Razorpay (T62), family-member
    // management (T63), and tips (T64) each own their own call sites
    // elsewhere and are not wired through here.

    /// `getPremiumPlans` — `GET /premium/plans`. Platform is resolved
    /// server-side from the `os` request header
    /// (`HTTPClient.headers()`), not a query param here — there is no
    /// client-supplied platform override.
    static let premiumPlans = Endpoint.get("/premium/plans")

    /// `createPaymentRequest` — `GET /premium/payment/request/:planId?provider=`.
    /// `provider` is always `"APPLE"` from this build (see
    /// `RemoteSubscriptionRepository`'s doc comment).
    static func createPaymentRequest(planId: String, provider: String) -> Endpoint {
        .get("/premium/payment/request/\(planId)?provider=\(provider)")
    }

    /// `verifyPayment` — `POST /premium/payment/success`, body
    /// `{provider, orderId, payload}`.
    static let paymentSuccess = Endpoint.post("/premium/payment/success")

    /// `cancelSubscriptionApi` (`end_points.dart:313`) — `GET
    /// /premium/subscription/cancel`; replies `{data: <membership>}`. Only
    /// reached for a web-checkout (Razorpay) subscription — Apple's is
    /// cancelled in the App Store.
    static let cancelSubscription = Endpoint.get("/premium/subscription/cancel")
}
