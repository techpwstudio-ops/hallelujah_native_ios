import SwiftUI

/// Ports `ManageFamilyMembersPage` (`lib/views/subscription/ManageFamilyMembersPage.dart`)
/// plus its sheets (`showInviteMemberSheet`, `showInviteSentSheet`,
/// `showRemoveMemberSheet`, `showCancelInviteConfirmationSheet`). Presented
/// from `AppRoute.manageFamilyMembers`.
///
/// Deviation kept from the earlier native cut: `MemberTile`'s Remove is wired
/// for real (Dart leaves it a `// TODO`), using `showRemoveMemberSheet`'s UI.
/// Invite send failures show inline in the sheet (Flutter uses a snackbar).
struct ManageFamilyMembersView: View {
    @State private var viewModel = ManageFamilyMembersViewModel()
    @State private var isInviteSheetPresented = false
    @State private var inviteValidationError: String?
    @State private var sentIdentifier: String?
    @State private var showSentSheet = false
    @State private var memberPendingRemoval: FamilyMember?
    @State private var invitePendingCancellation: FamilyInvite?

    @Environment(\.toastCenter) private var toastCenter

    var body: some View {
        content
            .parityScaffold()
            .parityNavTitle("Manage Family Members")
            .task { await viewModel.load() }
            .parityFitSheet(isPresented: $isInviteSheetPresented, dismissible: false, onDismiss: presentSentIfNeeded) {
                InviteMemberSheet(
                    isSending: viewModel.isSendingInvite,
                    errorMessage: inviteValidationError ?? viewModel.sendInviteErrorMessage,
                    onCancel: { isInviteSheetPresented = false },
                    onSend: sendInvite
                )
            }
            .parityFitSheet(isPresented: $showSentSheet) {
                InviteSentSheet(identifier: sentIdentifier ?? "") { showSentSheet = false }
            }
            .parityFitSheet(item: $memberPendingRemoval) { member in
                ParityConfirmSheet(
                    title: "Remove Member",
                    message: "Remove \(member.name) from Family Plan?",
                    cancelTitle: "Cancel",
                    confirmTitle: "Remove Member",
                    onCancel: { memberPendingRemoval = nil },
                    onConfirm: { confirmRemoveMember(member) }
                )
            }
            .parityFitSheet(item: $invitePendingCancellation) { invite in
                ParityConfirmSheet(
                    title: "Cancel Invite",
                    message: "Do you wish to cancel the invite?",
                    cancelTitle: "Back",
                    confirmTitle: "Cancel Invite",
                    onCancel: { invitePendingCancellation = nil },
                    onConfirm: { confirmCancelInvitation(invite) }
                )
            }
    }

    // MARK: Actions

    private func sendInvite(_ identifier: String) {
        guard ManageFamilyMembersViewModel.isValidIdentifier(identifier) else {
            inviteValidationError = String(localized: "Please enter valid email or mobile")
            return
        }
        inviteValidationError = nil
        Task {
            if await viewModel.sendInvitation(identifier: identifier) {
                sentIdentifier = identifier
                isInviteSheetPresented = false
            }
        }
    }

    private func presentSentIfNeeded() {
        inviteValidationError = nil
        if sentIdentifier != nil { showSentSheet = true }
    }

    private func confirmRemoveMember(_ member: FamilyMember) {
        memberPendingRemoval = nil
        Task {
            let message = await viewModel.removeMember(member)
            toastCenter.show(message)
        }
    }

    private func confirmCancelInvitation(_ invite: FamilyInvite) {
        invitePendingCancellation = nil
        Task {
            let message = await viewModel.cancelInvitation(invite)
            toastCenter.show(message)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .tint(AccountParity.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text("Something went wrong")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let data = viewModel.data {
                    Text("Share Premium with up to \(max(data.maxMembers - 1, 0)) family members.")
                        .font(AccountParity.headlineSmall)
                        .foregroundStyle(AccountParity.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer().frame(height: 24)
                    MembersCountChip(current: data.totalMembers, max: data.maxMembers)
                    Spacer().frame(height: 20)

                    ForEach(data.members) { member in
                        MemberTile(member: member) { memberPendingRemoval = member }
                    }

                    Rectangle().fill(AccountParity.white12).frame(height: 1)
                        .padding(.vertical, 16)

                    if !data.invites.isEmpty {
                        Text("Invited Members")
                            .font(AccountParity.titleMedium)
                            .foregroundStyle(AccountParity.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer().frame(height: 12)
                        ForEach(data.invites) { invite in
                            InviteTile(
                                invite: invite,
                                onResend: {
                                    Task {
                                        let message = await viewModel.resendInvitation(invite)
                                        toastCenter.show(message)
                                    }
                                },
                                onCancel: { invitePendingCancellation = invite }
                            )
                        }
                        Spacer().frame(height: 16)
                    }
                    Spacer().frame(height: 16)

                    AddMemberButton(isDisabled: data.totalMembers >= data.maxMembers) {
                        inviteValidationError = nil
                        sentIdentifier = nil
                        isInviteSheetPresented = true
                    }
                }
            }
            .padding(Dimens.paddingLarge)
            // Native-only tablet/Mac adaptation (no Flutter counterpart).
            .readableContentWidth()
        }
        .refreshable { await viewModel.refresh() }
    }
}

/// `MemberTile`: 36pt rounded-square avatar, name + "Family Manager", email, red Remove.
private struct MemberTile: View {
    let member: FamilyMember
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: ArtworkURLResolver().resolve(
                    path: member.image, variant: .sm, allowedVariants: member.imageVariants
                ),
                width: Dimens.userThumbnailSize,
                height: Dimens.userThumbnailSize,
                cornerRadius: Dimens.cornerRadius
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(AccountParity.font(14, .semibold))
                        .foregroundStyle(AccountParity.white)
                    if member.isOwner {
                        Text("Family Manager")
                            .font(AccountParity.font(12))
                            .foregroundStyle(AccountParity.white54)
                    }
                }
                Text(member.email)
                    .font(AccountParity.font(12))
                    .foregroundStyle(AccountParity.white54)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !member.isOwner {
                Button(action: onRemove) {
                    Text("Remove")
                        .font(AccountParity.font(14, .medium))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
    }
}

/// `MembersCountChip`.
private struct MembersCountChip: View {
    let current: Int
    let max: Int

    var body: some View {
        Text("\(current) of \(max) Members added")
            .font(AccountParity.font(12))
            .foregroundStyle(AccountParity.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AccountParity.white10))
            .frame(maxWidth: .infinity)
    }
}

/// `AddMemberButton`: dotted rounded rect (`[6, 3]`, 1.2pt), 16pt vertical padding.
private struct AddMemberButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Add Member")
                .font(AccountParity.font(14, .medium))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.38) : AccountParity.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(
                            isDisabled ? AccountParity.white24 : Color.white.opacity(0.38),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [6, 3])
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// `InviteTile` + `inviteStatusText` / `inviteStatusColor`.
private struct InviteTile: View {
    let invite: FamilyInvite
    let onResend: () -> Void
    let onCancel: () -> Void

    private var showsResend: Bool {
        invite.status == "expired" || invite.status == "cancelled"
    }

    private var statusText: String {
        switch invite.status {
        case "pending": String(localized: "Pending")
        case "expired": String(localized: "Expired")
        case "cancelled": String(localized: "Cancelled")
        case "accepted": String(localized: "Joined")
        default: invite.status
        }
    }

    /// `Colors.orangeAccent` / `grey` / `redAccent` / `green` / `white54`.
    private var statusColor: Color {
        switch invite.status {
        case "pending": Color(red: 1.0, green: 0xAB / 255, blue: 0x40 / 255)
        case "expired": AccountParity.grey
        case "cancelled": Color(red: 1.0, green: 0x52 / 255, blue: 0x52 / 255)
        case "accepted": Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
        default: AccountParity.white54
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .font(.system(size: 18))
                .foregroundStyle(AccountParity.white54)
                .frame(width: Dimens.userThumbnailSize, height: Dimens.userThumbnailSize)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(AccountParity.white10)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(invite.displayText)
                    .font(AccountParity.font(14, .semibold))
                    .foregroundStyle(AccountParity.white)
                Text(statusText)
                    .font(AccountParity.font(12))
                    .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                if showsResend {
                    Button(action: onResend) {
                        Text("Resend")
                            .font(AccountParity.font(14, .medium))
                            .foregroundStyle(Color(red: 0x69 / 255, green: 0xF0 / 255, blue: 0xAE / 255))
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AccountParity.font(14, .medium))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
    }
}
