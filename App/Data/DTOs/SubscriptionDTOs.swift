import Foundation

/// `getPremiumPlans` (`subscriptions.controller.js`) — `{success, platform,
/// country, data: [SubscriptionPlan]}`. Only `data` has a native call site;
/// `platform`/`country` are informational echoes of what the server already
/// resolved from this request's own `os` header (`HTTPClient.headers()`).
struct PremiumPlansResponse: Decodable, Sendable {
    let data: [SubscriptionPlan]
}

/// `createPaymentRequest` (`payment.controller.js`) returns
/// `paymentService.create`'s APPLE/GOOGLE branch verbatim
/// (`payment.service.js`: `return res.json(payment)`) —
/// `{success: true, data: {orderId, providerPlanId, price, currency}}`.
struct PaymentOrderResponse: Decodable, Sendable {
    let data: PaymentOrder
}

/// The value StoreKit actually buys against (`_productId`, Dart's
/// `PaymentService._startIAPPurchase`) is THIS response's `providerPlanId`,
/// not the plan list's own field of the same name — confirmed directly
/// against `payment_service.dart:74` (`_productId = data["providerPlanId"]`
/// inside `createOrder`, not inside the plans fetch). The order is the
/// freshest resolution of plan → Apple product ID; the plan list's copy can
/// be stale by the time a purchase actually starts.
struct PaymentOrder: Decodable, Sendable, Equatable {
    let orderId: String
    let providerPlanId: String?
    let price: Double?
    let currency: String?
}

/// `verifyPayment` (`payment.controller.js`) — `data` carries the full
/// `getUserMembershipDetails` shape on real success, and is ABSENT (only
/// `message` present) on the "already verified" short-circuit
/// (`order.status === paid`, itself still a 200) — `decodeIfPresent`
/// handles both without a separate flag.
struct PaymentVerifyResponse: Decodable, Sendable {
    let message: String?
    let data: Membership?
}

/// Defensive `{message}` extraction for a non-2xx premium/payment response
/// body — same `JSONSerialization`-based shape as `AuthOTPError`
/// (`AuthOTPDTOs.swift`), narrowed to just `message`/`statusCode`: none of
/// `AuthOTPError`'s OTP-specific fields (`code`, `retryAfterSeconds`,
/// `fallbackChannel`) have a backend counterpart on these endpoints.
struct SubscriptionError: Error, Sendable, Equatable {
    let statusCode: Int
    let message: String

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rawMessage = (json["message"] as? String)?.trimmingCharacters(in: .whitespaces)
        message = (rawMessage?.isEmpty == false ? rawMessage : nil) ?? String(localized: "Something went wrong. Please try again.")
    }
}
