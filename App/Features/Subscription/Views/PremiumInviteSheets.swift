import SwiftUI

/// `Loader.show(isProcessingSheet: true, ...)` (`lib/services/loading_service.dart`):
/// drag handle, 56pt spinner, headlineSmall title, bodyMedium description.
struct ProcessingSheet: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 28)
            MaterialSpinner(color: .white, size: 56)
                .frame(width: 56, height: 56)
            Spacer().frame(height: 24)
            Text(title)
                .font(AccountParity.headlineSmall)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            Text(description)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 32)
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.vertical, 20)
    }
}

private struct PremiumInviteSheetsModifier: ViewModifier {
    @Bindable var coordinator: PremiumInviteCoordinator
    @Environment(\.toastCenter) private var toastCenter

    func body(content: Content) -> some View {
        content
            .parityFitSheet(
                item: $coordinator.stage,
                dismissible: coordinator.stage?.isDismissible ?? true
            ) { stage in
                switch stage {
                case let .invite(invite):
                    InviteReceivedSheet(
                        inviterName: invite.inviterName,
                        planName: invite.planName,
                        onAccept: {
                            Task { toastCenter.show(await coordinator.accept(invite)) }
                        },
                        onDecline: {
                            Task { toastCenter.show(await coordinator.decline(invite)) }
                        }
                    )
                case let .processing(title, description):
                    ProcessingSheet(title: title, description: description)
                case .success:
                    SubscribedSuccessSheet { coordinator.stage = nil }
                }
            }
    }
}

extension View {
    /// Hosts the invite-received flow (invite → processing → success). Apply
    /// once on the app shell and call `coordinator.present(...)` from the
    /// sync-payload / realtime-event handlers.
    func premiumInviteSheets(_ coordinator: PremiumInviteCoordinator) -> some View {
        modifier(PremiumInviteSheetsModifier(coordinator: coordinator))
    }
}
