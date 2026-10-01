import Foundation

/// `TipService`'s backend calls (`lib/services/tip_service.dart`'s
/// `createTipOrder`/`_verify`) against `/tips/request`/`/tips/success`
/// (`Endpoint+Tips.swift`). Both endpoints are confirmed not yet implemented
/// server-side (see `TipTier`'s doc comment) — this protocol is wired to the
/// real contract Dart's own source already describes, ready for the backend
/// to catch up.
protocol TipRepository: Sendable {
    /// `createTipOrder` — returns the created order's `orderId`. Dart reads
    /// nothing else out of the response map.
    func createTipOrder(amount: Int, note: String, creatorId: String?, songId: String?) async throws -> TipOrder

    /// `_verify` — `provider` is always `"APPLE"` on this build, same
    /// reasoning as `SubscriptionRepository.verifyPurchase`'s own hardcoded
    /// provider. Throws on any non-200 response; Dart's own success check is
    /// `res.statusCode == 200` with no body inspection on success, so there
    /// is nothing meaningful to return beyond "didn't throw."
    func verifyTip(orderId: String, receiptData: String, productId: String) async throws
}
