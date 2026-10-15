import SwiftUI

/// Ports `lib/sheets/account_deletion/showAccountDeletionSheet.dart`
/// ("Deletion Scheduled") and `showAccountRestoredSheet.dart`. Present with
/// `.parityFitSheet(isPresented:cornerRadius: 24, dismissible: false)` for the
/// scheduled sheet (Flutter: transparent, not dismissible, no drag, back
/// button blocked) and the default 28pt radius for the restored sheet.

enum AccountDeletionCopy {
    /// `_formatDate`: "5 Mar 2026", in the user's locale.
    static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// `_buildRemainingTimeText`.
    static func remainingTimeText(until deletionDate: Date, now: Date = Date()) -> String {
        let interval = deletionDate.timeIntervalSince(now)
        if interval < 0 {
            return String(localized: "Your account is scheduled for deletion very soon.")
        }
        let totalHours = Int(interval / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return days > 1
                ? String(localized: "You can cancel this request within the next \(days) days by logging in.")
                : String(localized: "You can cancel this request within the next \(days) day by logging in.")
        } else if hours > 0 {
            return hours > 1
                ? String(localized: "You can cancel this request within the next \(hours) hours.")
                : String(localized: "You can cancel this request within the next \(hours) hour.")
        }
        return String(localized: "You can cancel this request shortly before deletion.")
    }
}

struct AccountDeletionScheduledSheet: View {
    let deletionDate: Date
    var isWorking: Bool = false
    let onCancelDeletion: () -> Void
    let onCloseApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            Text("Deletion Scheduled")
                .font(AccountParity.font(24, .semibold))
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            Text("Your account is scheduled for deletion on \(AccountDeletionCopy.formatDate(deletionDate)).")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            Text(AccountDeletionCopy.remainingTimeText(until: deletionDate))
                .font(AccountParity.bodySmall)
                .foregroundStyle(AccountParity.white60)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 24)
            ParitySheetButton(
                title: "Cancel Deletion", radius: 14, verticalPadding: 14,
                isLoading: isWorking, action: onCancelDeletion
            )
            Spacer().frame(height: 12)
            Button(action: onCloseApp) {
                Text("Close App")
                    .font(AccountParity.font(11))
                    .tracking(0.5)
                    .foregroundStyle(AccountParity.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// Auto-closes after 3 seconds.
struct AccountRestoredSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 24)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30))
                .foregroundStyle(AccountParity.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.white.opacity(0.1)))
            Spacer().frame(height: 20)
            Text("Your account is active again.")
                .font(AccountParity.font(24, .semibold))
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 10)
            Text("All data remains unchanged.")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            onClose()
        }
    }
}

// MARK: - Hosting

private struct AccountDeletionPendingModifier: ViewModifier {
    @Bindable var coordinator: AccountDeletionPendingCoordinator
    @Environment(\.toastCenter) private var toastCenter

    func body(content: Content) -> some View {
        content
            .parityFitSheet(
                item: $coordinator.stage,
                cornerRadius: coordinator.stage == .restored ? 28 : 24,
                dismissible: coordinator.stage == .restored
            ) { stage in
                switch stage {
                case let .scheduled(date):
                    AccountDeletionScheduledSheet(
                        deletionDate: date,
                        isWorking: coordinator.isWorking,
                        onCancelDeletion: {
                            Task {
                                if let message = await coordinator.cancelDeletion() {
                                    toastCenter.show(message)
                                }
                            }
                        },
                        // `exit(0)` in Dart.
                        onCloseApp: { exit(0) }
                    )
                case .restored:
                    AccountRestoredSheet { coordinator.stage = nil }
                }
            }
    }
}

extension View {
    /// Hosts the blocking "Deletion Scheduled" sheet and its "account restored"
    /// follow-up. Apply once on the app shell.
    func accountDeletionPendingSheets(_ coordinator: AccountDeletionPendingCoordinator) -> some View {
        modifier(AccountDeletionPendingModifier(coordinator: coordinator))
    }
}
