import Foundation

/// `TipService`'s HTTP calls (`lib/services/tip_service.dart`) against the
/// `/tips/*` contract (`Endpoint+Tips.swift`). `provider` is always
/// `"APPLE"` here, same reasoning as `RemoteSubscriptionRepository`.
final class RemoteTipRepository: TipRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func offerings() async -> [Offering] {
        do {
            let response = try await client.send(.offerings, silent: true)
            guard response.statusCode == 200 else { return [] }
            return Offering.parseList(response.data)
        } catch {
            return []
        }
    }

    func createTipOrder(offering: Offering, note: String, creatorId: String?, songId: String?) async throws -> TipOrder {
        let body = try JSONEncoder().encode(CreateTipOrderRequest(
            offeringId: offering.id,
            note: note,
            creatorId: creatorId,
            songId: songId,
            provider: "APPLE"
        ))
        let response = try await client.send(.createTipRequest, body: body)
        guard response.statusCode == 200 else {
            throw TipError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(TipOrderResponse.self, from: response.data)
        return decoded.data
    }

    func verifyTip(orderId: String, receiptData: String, productId: String) async throws {
        let body = try JSONEncoder().encode(VerifyTipRequest(
            provider: "APPLE",
            orderId: orderId,
            payload: VerifyTipRequest.ApplePayload(receiptData: receiptData, productId: productId)
        ))
        let response = try await client.send(.tipSuccess, body: body)
        guard response.statusCode == 200 else {
            throw TipError(statusCode: response.statusCode, data: response.data)
        }
    }
}

/// `createTipOrder`'s request body (`tip_service.dart`):
/// `{offeringId, note, creatorId, songId, provider}`, verbatim.
private struct CreateTipOrderRequest: Encodable {
    let offeringId: String
    let note: String
    let creatorId: String?
    let songId: String?
    let provider: String
}

/// `_verify`'s request body (`tip_service.dart`): `{provider, orderId,
/// payload}`; `payload`'s APPLE branch is `{receiptData, productId}` exactly
/// (`verifyTipPurchase`'s `{'receiptData': token, 'productId': ...}`).
private struct VerifyTipRequest: Encodable {
    let provider: String
    let orderId: String
    let payload: ApplePayload

    struct ApplePayload: Encodable {
        let receiptData: String
        let productId: String
    }
}
