import Foundation

/// Ports `SubscriptionPlanModel`/`BillingCycle`
/// (`lib/models/subscription_plan_model.dart`), against the real
/// `GET /premium/plans` response (`getPremiumPlans`,
/// `src/controllers/user/subscriptions.controller.js`) rather than Dart's
/// model alone — that controller's mapped-plan shape is the source of
/// truth for field names/nullability, Dart's model just confirms which of
/// those fields already have a native-app consumer.
/// A plan's free period (`FreeTrial` in `subscription_plan_model.dart`);
/// `nil` on the plan when the API sends no block or both counts are zero.
struct PlanFreeTrial: Sendable, Equatable, Codable {
    let months: Int
    let days: Int

    /// `nil` when both counts are zero/negative.
    init?(months: Int, days: Int) {
        let m = max(0, months), d = max(0, days)
        guard m > 0 || d > 0 else { return nil }
        self.months = m
        self.days = d
    }

    private enum Keys: String, CodingKey { case months, days }
    private struct Empty: Error {}

    /// Tolerates counts sent as numbers or numeric strings, like Dart's
    /// `int.tryParse(value.toString())`; an all-zero block throws so the
    /// plan's optional decode collapses to `nil`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func count(_ key: Keys) -> Int {
            if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
            if let s = try? c.decodeIfPresent(String.self, forKey: key), let n = Int(s) { return n }
            return 0
        }
        guard let trial = PlanFreeTrial(months: count(.months), days: count(.days)) else { throw Empty() }
        self = trial
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(months, forKey: .months)
        try c.encode(days, forKey: .days)
    }
}

enum BillingCycle: String, Sendable, Equatable, Codable {
    case monthly
    case yearly
}

struct SubscriptionPlan: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    /// `nil` when `unpriced` — the catalogue matched this plan for the
    /// caller's platform/country but no active price row exists for it.
    /// Never a guessed/fallback number (see the controller's own comment on
    /// why it stopped hard-coding a price here).
    let price: Double?
    let currency: String?
    let billingCycle: BillingCycle
    let maxMembers: Int
    let isActive: Bool
    /// Lower-cased rail names this plan is buyable through on the caller's
    /// platform — e.g. `["apple"]`. Only used to detect a plan Apple can't
    /// buy at all; `providerPlanId` below is what actually drives StoreKit.
    let providers: [String]
    /// The Apple product identifier for this plan, already resolved
    /// server-side for the `ios` platform (`os` request header) — `nil` if
    /// this plan has no Apple mapping yet.
    let providerPlanId: String?
    let freeTrial: PlanFreeTrial?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, currency, billingCycle
        case maxMembers, isActive, providers, providerPlanId, freeTrial
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // `description` on the wire is Dart's `Map<String, dynamic>?` — a
        // rich block, not a plain string. No native call site reads inside
        // it yet, so this only preserves it as a display string when the
        // server ever sends one; a dictionary shape decodes to `nil` rather
        // than throwing.
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        billingCycle = try container.decode(BillingCycle.self, forKey: .billingCycle)
        maxMembers = try container.decodeIfPresent(Int.self, forKey: .maxMembers) ?? 1
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        providers = try container.decodeIfPresent([String].self, forKey: .providers) ?? []
        providerPlanId = try container.decodeIfPresent(String.self, forKey: .providerPlanId)
        freeTrial = (try? container.decodeIfPresent(PlanFreeTrial.self, forKey: .freeTrial)) ?? nil
    }
}

extension SubscriptionPlan {
    var isFamilyPlan: Bool { maxMembers > 1 }

    /// Whether this plan can be bought on this build at all — T61 only
    /// wires the Apple/StoreKit rail (T62 owns Razorpay); a plan whose only
    /// provider is Razorpay has nothing to purchase through yet.
    var isPurchasableOnThisBuild: Bool { providerPlanId != nil }
}
