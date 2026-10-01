import Foundation

/// Ports `FamilyMember`/`InviteModel`/`FamilyMembersResponse`
/// (`lib/river_pods/family_members_provider.dart`) — the data shape behind
/// `ManageFamilyMembersPage.dart`. Real endpoint: `GET
/// /premium/subscription/members` (`EndPoints.getSubscriptionMembersApi`),
/// response `{data: {subscriptionId, totalMembers, maxMembers, members:
/// [{id, role, user: {name, email, image, imageVariants}}], invites: [{id,
/// status, email, mobile}]}}` — confirmed directly against
/// `family_members_provider.dart`'s own `fromJson` methods, not just the
/// page that consumes them.
struct FamilyMember: Sendable, Equatable, Identifiable, Decodable {
    let id: String
    let role: String
    let name: String
    let email: String
    let image: String?
    let imageVariants: String?

    /// `member.role == "owner"` (`ManageFamilyMembersPage.dart`'s
    /// `MemberTile`) — the family manager, never shown a "Remove" button.
    var isOwner: Bool { role == "owner" }

    private enum CodingKeys: String, CodingKey {
        case id, role, user
    }

    /// `json['user'] ?? {}` (Dart) — a missing/null `user` sibling decodes
    /// to empty name/email rather than throwing.
    private struct UserPayload: Decodable {
        let name: String?
        let email: String?
        let image: String?
        let imageVariants: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        let user = try? container.decode(UserPayload.self, forKey: .user)
        name = user?.name ?? ""
        email = user?.email ?? ""
        image = user?.image
        imageVariants = user?.imageVariants
    }
}

/// Ports `InviteModel`. `displayText`/status helpers stay out of this type —
/// `inviteStatusText`/`inviteStatusColor` (`ManageFamilyMembersPage.dart`)
/// map status to a UI label/color, which belongs in the View layer, not here
/// (same layering `ArtworkURLResolver`'s doc comment calls out for keeping
/// `AppConfiguration`/UI concerns out of lower layers).
struct FamilyInvite: Sendable, Equatable, Identifiable, Decodable {
    let id: String
    let status: String
    let email: String?
    let mobile: String?

    /// `InviteModel.displayText` ported verbatim.
    var displayText: String { email ?? mobile ?? "Unknown" }

    func updatingStatus(_ status: String) -> FamilyInvite {
        FamilyInvite(id: id, status: status, email: email, mobile: mobile)
    }
}

/// Ports `FamilyMembersResponse` — the aggregate `data` payload, decoded
/// directly (the `{data: ...}` envelope itself lives in
/// `FamilyMembersResponseDTO`, `Data/DTOs/FamilyMembersDTOs.swift`).
struct FamilyMembers: Sendable, Equatable, Decodable {
    let subscriptionId: String
    let totalMembers: Int
    let maxMembers: Int
    let members: [FamilyMember]
    let invites: [FamilyInvite]
}

extension FamilyMembers {
    /// Ports `FamilyMembersNotifier.updateInviteStatus` — a local splice, no
    /// refetch.
    func updatingInviteStatus(_ inviteId: String, status: String) -> FamilyMembers {
        FamilyMembers(
            subscriptionId: subscriptionId,
            totalMembers: totalMembers,
            maxMembers: maxMembers,
            members: members,
            invites: invites.map { $0.id == inviteId ? $0.updatingStatus(status) : $0 }
        )
    }

    /// Ports `FamilyMembersNotifier.appendInvite` — prepends, matching
    /// Dart's `invites.insert(0, ...)`.
    func prependingInvite(_ invite: FamilyInvite) -> FamilyMembers {
        FamilyMembers(
            subscriptionId: subscriptionId,
            totalMembers: totalMembers,
            maxMembers: maxMembers,
            members: members,
            invites: [invite] + invites
        )
    }

    /// Ports `FamilyMembersNotifier.deleteInvite`.
    func removingInvite(_ inviteId: String) -> FamilyMembers {
        FamilyMembers(
            subscriptionId: subscriptionId,
            totalMembers: totalMembers,
            maxMembers: maxMembers,
            members: members,
            invites: invites.filter { $0.id != inviteId }
        )
    }

    /// Ports `FamilyMembersNotifier.deleteMember` — splices `members` only.
    /// Dart's own `copyWith` leaves `totalMembers` untouched here too (it
    /// only accepts `invites`/`members` overrides), so the "`X` of `Y`
    /// Members added" chip and the add-button's capacity check both stay
    /// stale until the next `fetch()`/pull-to-refresh — a real quirk in the
    /// reference, ported as-is rather than silently fixed.
    func removingMember(_ memberId: String) -> FamilyMembers {
        FamilyMembers(
            subscriptionId: subscriptionId,
            totalMembers: totalMembers,
            maxMembers: maxMembers,
            members: members.filter { $0.id != memberId },
            invites: invites
        )
    }
}
