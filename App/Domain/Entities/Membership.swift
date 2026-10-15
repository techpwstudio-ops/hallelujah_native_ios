import Foundation

/// Ports `Membership`/`Subscription` (`lib/models/dart/membership_model.dart`).
/// The wire shape is nested (`getUserMembershipDetails`,
/// `src/utils/users.helpers.js`): `subscription.plan.maxMembers` and
/// `subscription.provider.provider`, not flattened — confirmed directly
/// against the backend helper and re-confirmed against Dart's own
/// `Subscription.fromJson`, which reads those same two nested paths rather
/// than assuming the server ever flattens them.
struct Membership: Sendable, Equatable, Codable {
    let role: String
    let subscription: Subscription

    var isOwner: Bool { role == "owner" }
}

struct Subscription: Sendable, Equatable, Codable {
    let id: String
    let planId: String
    let planName: String
    /// `subscription.provider?.provider` — "APPLE"/"GOOGLE"/"RAZORPAY", or
    /// `nil` for a subscription with no provider row yet.
    let providerName: String?
    let ownerId: String
    let status: String
    let startDate: Date
    let endDate: Date
    let autoRenew: Bool
    let maxMembers: Int

    enum CodingKeys: String, CodingKey {
        case id, planId, planName, ownerId, status, startDate, endDate, autoRenew
        case plan, provider
    }

    /// `User.swift` carries this same fallback privately (Prisma's
    /// `DateTime` serializes WITH fractional seconds —
    /// `"2024-01-10T08:30:00.000Z"` — which `JSONDecoder`'s bare `.iso8601`
    /// strategy rejects); decoding `startDate`/`endDate` as raw strings
    /// through `Date.parseFlexibleISO8601` here instead of
    /// `container.decode(Date.self, ...)` makes this type self-contained
    /// regardless of which `JSONDecoder` a caller happens to use, rather
    /// than silently depending on the caller picking a decoder whose
    /// `dateDecodingStrategy` tolerates fractional seconds.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    private enum PlanKeys: String, CodingKey {
        case maxMembers
    }

    private enum ProviderKeys: String, CodingKey {
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        planId = try container.decode(String.self, forKey: .planId)
        planName = try container.decode(String.self, forKey: .planName)
        ownerId = try container.decode(String.self, forKey: .ownerId)
        status = try container.decode(String.self, forKey: .status)
        guard let decodedStartDate = Date.parseFlexibleISO8601(try container.decode(String.self, forKey: .startDate)) else {
            throw DecodingError.dataCorruptedError(forKey: .startDate, in: container, debugDescription: "Not a valid ISO 8601 date")
        }
        startDate = decodedStartDate
        guard let decodedEndDate = Date.parseFlexibleISO8601(try container.decode(String.self, forKey: .endDate)) else {
            throw DecodingError.dataCorruptedError(forKey: .endDate, in: container, debugDescription: "Not a valid ISO 8601 date")
        }
        endDate = decodedEndDate
        autoRenew = try container.decodeIfPresent(Bool.self, forKey: .autoRenew) ?? true

        let planContainer = try? container.nestedContainer(keyedBy: PlanKeys.self, forKey: .plan)
        maxMembers = (try planContainer?.decodeIfPresent(Int.self, forKey: .maxMembers)) ?? 0

        let providerContainer = try? container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .provider)
        providerName = try providerContainer?.decodeIfPresent(String.self, forKey: .provider)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(planId, forKey: .planId)
        try container.encode(planName, forKey: .planName)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(status, forKey: .status)
        try container.encode(Self.isoFormatter.string(from: startDate), forKey: .startDate)
        try container.encode(Self.isoFormatter.string(from: endDate), forKey: .endDate)
        try container.encode(autoRenew, forKey: .autoRenew)

        var planContainer = container.nestedContainer(keyedBy: PlanKeys.self, forKey: .plan)
        try planContainer.encode(maxMembers, forKey: .maxMembers)

        if let providerName {
            var providerContainer = container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .provider)
            try providerContainer.encode(providerName, forKey: .provider)
        }
    }
}

extension Subscription {
    /// `Subscription.isActive` (Dart) — Dart's own getter has an unreachable
    /// second `return` after an unconditional first one
    /// (`startDate.isBefore(now) && endDate.isAfter(now)` never runs); that's
    /// a bug in the reference, not ported.
    var isActive: Bool { endDate > Date() }

    /// Cancelled but still inside the paid period.
    var isCanceled: Bool { status == "cancelled" }

    var isExpired: Bool { Date() > endDate }

    var willRenew: Bool { autoRenew }

    var remainingDays: Int {
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(diff, 0)
    }

    var displayStatus: String {
        if isActive, isCanceled {
            return String(localized: "Premium (Ends in \(remainingDays) days)")
        } else if isActive {
            return String(localized: "Premium")
        } else {
            return String(localized: "Explore Premium")
        }
    }
}
