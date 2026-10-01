import Foundation

extension Endpoint {
    // MARK: Tips (T64) — `lib/services/tip_service.dart`'s
    // `EndPoints.createTipRequestApi`/`EndPoints.tipSuccessApi`
    // (`end_points.dart`). Both are explicitly commented TODO(backend) in
    // the Dart source, and confirmed absent from the backend repo (no tip
    // route/controller file exists there) — wired to the real paths anyway
    // so the flow works once the backend lands them, same posture every
    // other confirmed-but-not-yet-live gap in this port already uses.

    /// `createTipRequestApi` — `POST /tips/request`.
    static let createTipRequest = Endpoint.post("/tips/request")

    /// `tipSuccessApi` — `POST /tips/success`.
    static let tipSuccess = Endpoint.post("/tips/success")
}
