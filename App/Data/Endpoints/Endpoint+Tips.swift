import Foundation

extension Endpoint {
    // MARK: Tips — `EndPoints.offeringsApi` / `createTipRequestApi` /
    // `tipSuccessApi` (`end_points.dart`, `ai` branch).

    /// `GET /offerings` — the tip amounts for this device's store (the server
    /// reads the `os` header).
    static let offerings = Endpoint.get("/offerings")

    /// `POST /tips/request` — body `{offeringId, note, creatorId, songId,
    /// provider}`; returns `{orderId, productId, amount, currency}`.
    static let createTipRequest = Endpoint.post("/tips/request")

    /// `POST /tips/success` — verifies the store receipt (body `{provider,
    /// orderId, payload}`).
    static let tipSuccess = Endpoint.post("/tips/success")
}
