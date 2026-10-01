import Foundation

/// `createTipOrder`'s response (`tip_service.dart`) — `{data: {orderId}}`.
/// Dart reads only `orderId` out of the decoded map before discarding the
/// rest (`order['orderId'] as String?`), so this mirrors exactly that one
/// field.
struct TipOrderResponse: Decodable, Sendable {
    let data: TipOrder
}

struct TipOrder: Decodable, Sendable, Equatable {
    let orderId: String
}

/// Defensive `{message}` extraction for a non-2xx tip-endpoint response
/// body, same shape and reasoning as `SubscriptionError` — one copy per
/// feature boundary rather than a shared generic error type, matching that
/// file's own precedent.
struct TipError: Error, Sendable, Equatable {
    let statusCode: Int
    let message: String

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rawMessage = (json["message"] as? String)?.trimmingCharacters(in: .whitespaces)
        message = (rawMessage?.isEmpty == false ? rawMessage : nil) ?? "Something went wrong. Please try again."
    }
}
