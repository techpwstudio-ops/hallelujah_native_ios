import Foundation

extension Endpoint {
    // MARK: Family members (T63) — `manage_premium_service.dart`'s
    // family-member call sites, routes confirmed against
    // `end_points.dart:307-323`. `acceptSubscriptionInviteApi`/
    // `declineSubscriptionInviteApi` have no case here — see
    // `FamilyMembersRepository`'s doc comment for why.

    /// `getSubscriptionMembersApi` — `/premium/subscription/members`.
    static let familyMembers = Endpoint.get("/premium/subscription/members")

    /// `sendSubscriptionMemberInviteApi` — `/premium/subscription/invite`,
    /// body `{identifier}`.
    static let sendFamilyMemberInvite = Endpoint.post("/premium/subscription/invite")

    /// `resendSubscriptionInviteApi` — `/premium/subscription/invite/resend`,
    /// body `{inviteId}` (the invite id travels in the body here, not the
    /// path — unlike cancel/remove below).
    static let resendFamilyMemberInvite = Endpoint.post("/premium/subscription/invite/resend")

    /// `deleteSubscriptionInviteApi(inviteId) => '/premium/subscription/invite/$inviteId'`.
    static func cancelFamilyMemberInvite(inviteId: String) -> Endpoint {
        .delete("/premium/subscription/invite/\(inviteId)")
    }

    /// `deleteSubscriptionMemberApi(memberId) => '/premium/subscription/member/$memberId'`.
    static func removeFamilyMember(memberId: String) -> Endpoint {
        .delete("/premium/subscription/member/\(memberId)")
    }
}
