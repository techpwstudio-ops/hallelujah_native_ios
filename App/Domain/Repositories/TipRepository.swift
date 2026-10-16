import Foundation

/// The tip flow's backend calls (`offering_provider.dart`,
/// `tip_service.dart`, `ai` branch).
protocol TipRepository: Sendable {
    /// `OfferingRepository.getOfferings` — never throws: a failure is an empty
    /// list, which the player reads as "no tipping right now" and hides the
    /// button.
    func offerings() async -> [Offering]

    /// `createTipOrder`. The backend prices the order from the offering id
    /// alone — the app never sends an amount.
    func createTipOrder(offering: Offering, note: String, creatorId: String?, songId: String?) async throws -> TipOrder

    /// `submitReceipt`. Throws on any non-200 response.
    func verifyTip(orderId: String, receiptData: String, productId: String) async throws
}
