import Foundation

/// Ports `ManagePremiumService`'s family-member call sites
/// (`lib/services/manage_premium_service.dart`) against the real
/// `/premium/subscription/*` contract (`end_points.dart:307-323`). Deliberately
/// separate from `SubscriptionRepository` — that protocol's own doc comment
/// reserves family-member management for T63 without adding a method there,
/// matching how T62 (Razorpay)/T64 (Tips) each own their own call sites too.
///
/// `acceptInvitation`/`declineInvitation` back the invite *recipient's*
/// sheet (`showInviteReceivedSheet`, `PremiumInviteCoordinator`), reached from
/// the sync payload's `invite` key or the `premium.member.invite` realtime
/// event.
///
/// Every success returns the server's own `message` (Dart toasts
/// `res.data['message']` verbatim after each of these calls).
protocol FamilyMembersRepository: Sendable {
    /// `getSubscriptionMembers` — `GET /premium/subscription/members`.
    func fetchMembers() async throws -> FamilyMembers

    /// `ManagePremiumService.sendInvitation` — `POST
    /// /premium/subscription/invite`, body `{identifier}`. Returns the
    /// newly created invite (`res.data['data']`, the exact payload
    /// `appendInvite` decodes).
    func sendInvitation(identifier: String) async throws -> FamilyInvite

    /// `ManagePremiumService.resendInvitation` — `POST
    /// /premium/subscription/invite/resend`, body `{inviteId}`. Returns the
    /// invite's refreshed status (`res.data['data']['status']`), the exact
    /// value `updateInviteStatus` applies locally.
    func resendInvitation(inviteId: String) async throws -> FamilyInviteResendResult

    /// `ManagePremiumService.deleteInvitation` — `DELETE
    /// /premium/subscription/invite/:inviteId`.
    @discardableResult
    func cancelInvitation(inviteId: String) async throws -> String?

    /// `ManagePremiumService.deleteMember` — `DELETE
    /// /premium/subscription/member/:memberId`. The reference's own
    /// `MemberTile.onRemove` never calls this (`// TODO: remove member
    /// flow`, `ManageFamilyMembersPage.dart`) even though the service method
    /// is fully implemented — this task wires that missing call, since
    /// "add/remove member round-trips" is the done criterion.
    @discardableResult
    func removeMember(memberId: String) async throws -> String?

    /// `ManagePremiumService.acceptInvitation` — `POST
    /// /premium/subscription/invite/accept`, body `{inviteId}`. On 200 the
    /// body's `data` is the recipient's new membership
    /// (`OurSession.setMembershipDetails(res.data['data'])`).
    func acceptInvitation(inviteId: String) async throws -> FamilyInviteActionResult

    /// `ManagePremiumService.declineInvitation` — `POST
    /// /premium/subscription/invite/decline`, body `{inviteId}`.
    func declineInvitation(inviteId: String) async throws -> FamilyInviteActionResult
}

struct FamilyInviteResendResult: Sendable, Equatable {
    /// `res.data['data']['status']`.
    let status: String
    /// `res.data['message']`.
    let message: String?
}

struct FamilyInviteActionResult: Sendable, Equatable {
    let message: String?
    /// Accept only; `nil` for decline.
    let membership: Membership?
}
