import SwiftUI

/// Hosts the app-wide sheets that Flutter raises from services rather than
/// from a screen, and feeds them from the infrastructure that triggers them:
///
/// - `showInviteReceivedSheet` — raised by `DataService._fetchInitData` (the
///   payload's `invite` key) and by the `premium.member.invite` realtime
///   event (`RealtimeEventBus`);
/// - `showAccountDeletionSheet` — raised after every non-silent
///   `getInitData()` when the signed-in user carries a `deletingDate`.
///
/// Apply once on the signed-in shell: `.appInfrastructureHost()`.
private struct AppInfrastructureHostModifier: ViewModifier {
    @State private var inviteCoordinator = PremiumInviteCoordinator()
    @State private var deletionCoordinator = AccountDeletionPendingCoordinator()
    @State private var dataSync = AppDataSync.shared
    @State private var eventBus: RealtimeEventBus = DependencyContainer.current.resolve()
    @State private var loader = GlobalLoader.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if loader.isLoading {
                    BlockingSpinnerOverlay()
                }
            }
            .premiumInviteSheets(inviteCoordinator)
            .accountDeletionPendingSheets(deletionCoordinator)
            .onChange(of: dataSync.syncGeneration, initial: true) { _, _ in
                if let invite = dataSync.takePendingInvite() {
                    inviteCoordinator.present(
                        inviteId: invite.inviteId,
                        inviterName: invite.inviterName,
                        planName: invite.planName
                    )
                }
                Task { await deletionCoordinator.checkPendingDeletion() }
            }
            .onChange(of: eventBus.premiumInviteReceivedCount) { _, _ in
                guard let invite = eventBus.lastPremiumInvite else { return }
                inviteCoordinator.present(
                    inviteId: invite.inviteId,
                    inviterName: invite.inviterName,
                    planName: invite.planName
                )
            }
    }
}

extension View {
    /// See `AppInfrastructureHostModifier`.
    func appInfrastructureHost() -> some View {
        modifier(AppInfrastructureHostModifier())
    }
}
