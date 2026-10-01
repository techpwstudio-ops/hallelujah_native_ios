import Foundation

/// `PaymentService`'s Apple/StoreKit call sites
/// (`lib/services/payment_service.dart`) against the real `/premium/*`
/// contract. `provider` is always `"APPLE"` here — this repository has no
/// Razorpay/Google call sites (see `SubscriptionRepository`'s doc comment
/// for why, and T62/T63/T64 for where those rails live instead).
final class RemoteSubscriptionRepository: SubscriptionRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchPlans() async throws -> [SubscriptionPlan] {
        let response = try await client.send(.premiumPlans)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(PremiumPlansResponse.self, from: response.data)
        return decoded.data
    }

    func createPaymentRequest(planId: String) async throws -> PaymentOrder {
        let response = try await client.send(.createPaymentRequest(planId: planId, provider: "APPLE"))
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(PaymentOrderResponse.self, from: response.data)
        return decoded.data
    }

    func verifyPurchase(orderId: String, receiptData: String) async throws -> Membership? {
        let body = try JSONEncoder().encode(VerifyPaymentRequest(
            provider: "APPLE",
            orderId: orderId,
            payload: VerifyPaymentRequest.ApplePayload(receiptData: receiptData)
        ))
        let response = try await client.send(.paymentSuccess, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(PaymentVerifyResponse.self, from: response.data)
        return decoded.data
    }
}

/// `_verifyCore`'s request body (`payment_service.dart`):
/// `{provider, orderId, payload}`, `payload` shaped per-provider by
/// `_buildPayload` — APPLE's branch is `{"receiptData": ...}` exactly.
private struct VerifyPaymentRequest: Encodable {
    let provider: String
    let orderId: String
    let payload: ApplePayload

    struct ApplePayload: Encodable {
        let receiptData: String
    }
}
