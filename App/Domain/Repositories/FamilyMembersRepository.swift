import Foundation

/// Ports `ManagePremiumService`'s family-member call sites
/// (`lib/services/manage_premium_service.dart`) against the real
/// `/premium/subscription/*` contract (`end_points.dart:307-323`). Deliberately
/// separate from `SubscriptionRepository` — that protocol's own doc comment
/// reserves family-member management for T63 without adding a method there,
/// matching how T62 (Razorpay)/T64 (Tips) each own their own call sites too.
///
/// `acceptInvitation`/`declineInvitation` (`EndPoints.acceptSubscriptionInviteApi`/
/// `declineSubscriptionInviteApi`) have no method here — those back the
/// invite *recipient's* accept/decline screen (reached from a push
/// notification/deep link, per `ManagePremiumService.acceptInvitation`'s own
/// `NavigationService.back()` + `showSubscribedSuccessSheet()` flow), not
/// `ManageFamilyMembersPage` (the owner's management screen this ports).
/// That recipient-side flow has no native screen yet and is out of this
/// task's scope.
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
    func resendInvitation(inviteId: String) async throws -> String

    /// `ManagePremiumService.deleteInvitation` — `DELETE
    /// /premium/subscription/invite/:inviteId`.
    func cancelInvitation(inviteId: String) async throws

    /// `ManagePremiumService.deleteMember` — `DELETE
    /// /premium/subscription/member/:memberId`. The reference's own
    /// `MemberTile.onRemove` never calls this (`// TODO: remove member
    /// flow`, `ManageFamilyMembersPage.dart`) even though the service method
    /// is fully implemented — this task wires that missing call, since
    /// "add/remove member round-trips" is the done criterion.
    func removeMember(memberId: String) async throws
}
