import Foundation
import Observation

/// Recipient side of a family-plan invite: `showInviteReceivedSheet` plus
/// `ManagePremiumService.acceptInvitation` / `declineInvitation`
/// (`lib/sheets/subscription/showInviteReceivedSheet.dart`,
/// `lib/services/manage_premium_service.dart`).
///
/// Flutter raises the sheet from two places: the sync payload's `invite` key
/// (`data_service.dart`) and the `premium.member.invite` realtime event
/// (`realtime_event_handler.dart`, foreground only). Either source calls
/// `present(inviteId:inviterName:planName:)`; the shell hosts the sheet via
/// `.premiumInviteSheets(_:)` (`PremiumInviteSheets.swift`).
@MainActor
@Observable
final class PremiumInviteCoordinator {
    struct PendingInvite: Equatable, Sendable {
        let inviteId: String
        let inviterName: String
        let planName: String
    }

    /// One stage at a time; all stages share a constant identity so the sheet
    /// swaps content in place instead of dismissing and re-presenting.
    enum Stage: Equatable, Identifiable {
        case invite(PendingInvite)
        case processing(title: String, description: String)
        case success

        var id: String { "premium-invite" }

        var isDismissible: Bool {
            if case .processing = self { return false }
            return true
        }
    }

    var stage: Stage?

    private let repository: any FamilyMembersRepository
    private let membershipStore: MembershipStore
    private let logger = AppLogger(category: .subscription)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
        membershipStore = container.resolve()
    }

    /// Ignored while another invite stage is on screen (the sync payload and
    /// the realtime event can both fire for the same invite).
    func present(inviteId: String?, inviterName: String?, planName: String?) {
        guard stage == nil, let inviteId, !inviteId.isEmpty else { return }
        stage = .invite(PendingInvite(
            inviteId: inviteId,
            inviterName: inviterName ?? "",
            planName: planName ?? ""
        ))
    }

    /// `acceptInvitation`. Returns the toast text to show.
    func accept(_ invite: PendingInvite) async -> String {
        stage = .processing(
            title: "Accepting Invite...",
            description: "Please wait while we accepting your invite."
        )
        do {
            let result = try await repository.acceptInvitation(inviteId: invite.inviteId)
            if let membership = result.membership {
                await membershipStore.setMembership(membership)
            }
            // `NavigationService.back()` closes the processing sheet, then
            // `showSubscribedSuccessSheet()` opens the success one.
            stage = .success
            return result.message ?? "Invitation accepted."
        } catch let error as SubscriptionError {
            stage = nil
            return error.message
        } catch {
            logger.warning("accept invitation failed: \(error)")
            stage = nil
            return "Something went wrong"
        }
    }

    /// `declineInvitation`. Returns the toast text to show.
    func decline(_ invite: PendingInvite) async -> String {
        stage = .processing(
            title: "Declining Invite...",
            description: "Please wait while we decline your invite."
        )
        do {
            let result = try await repository.declineInvitation(inviteId: invite.inviteId)
            stage = nil
            return result.message ?? "Invitation declined."
        } catch let error as SubscriptionError {
            stage = nil
            return error.message
        } catch {
            logger.warning("decline invitation failed: \(error)")
            stage = nil
            return "Something went wrong"
        }
    }
}
