import Foundation

/// Ports `TipTier`/`TipProducts` (`lib/constants/tip_products.dart`).
///
/// TODO(store/backend): the `productID`s below are PLACEHOLDERS, carried
/// over verbatim from the Dart source's own TODO comment. Each must be
/// created as a Consumable product in App Store Connect with a matching
/// price before `TipPurchaseManager.sendTip` can resolve a real product —
/// `createTipOrder` (`RemoteTipRepository`) also hits two backend endpoints
/// (`/tips/request`, `/tips/success`, see `Endpoint+Tips.swift`) that are
/// confirmed absent from the backend repo (no tip route/controller file
/// exists there). Wired to the real contract anyway so the flow works once
/// both land, same "ready for the backend to catch up" posture the rest of
/// this port already uses for its own confirmed-but-not-yet-live gaps.
///
/// `TipProducts.step` (Dart's slider-granularity constant) is not ported:
/// it has no call site in Dart's own `Slider` either (`onChanged` snaps
/// straight to `nearestTier(value)`, with no `divisions:`), so it is dead
/// code there too.
struct TipTier: Sendable, Equatable {
    let amount: Int
    let productID: String
    let label: String?
    let isPopular: Bool
}

enum TipProducts {
    static let tiers: [TipTier] = [
        TipTier(amount: 99, productID: "tip_99", label: "Coffee", isPopular: false),
        TipTier(amount: 199, productID: "tip_199", label: "Cheers", isPopular: true),
        TipTier(amount: 499, productID: "tip_499", label: "Generous", isPopular: false),
        TipTier(amount: 899, productID: "tip_899", label: "Superfan", isPopular: false),
    ]

    static let defaultAmount = 199

    static var presetAmounts: [Int] { tiers.map(\.amount) }
    static var minAmount: Int { tiers.first!.amount }
    static var maxAmount: Int { tiers.last!.amount }

    static func isTipProduct(_ productID: String) -> Bool {
        tiers.contains { $0.productID == productID }
    }

    static func productID(forAmount amount: Int) -> String? {
        tiers.first { $0.amount == amount }?.productID
    }
}
