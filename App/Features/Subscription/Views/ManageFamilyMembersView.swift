import SwiftUI

/// Ports `ManageFamilyMembersPage` (`lib/views/subscription/ManageFamilyMembersPage.dart`)
/// and `showInviteMemberSheet` (`lib/sheets/subscription/showInviteMemberSheet.dart`).
/// Presented from `AppRoute.manageFamilyMembers`.
///
/// Adaptations from the Dart reference:
/// - `showInviteMemberSheet`'s own secondary `showInviteSentSheet` confirmation
///   is replaced with a toast (`ToastCenter`) — one less modal hop, same
///   end-state confirmation.
/// - The reference has no cancel/remove confirmation at all (`deleteInvitation`/
///   `deleteMember` fire immediately on tap); this adds a native
///   `.confirmationDialog` before both, matching this app's own destructive-
///   action convention elsewhere rather than a silent irreversible tap.
/// - `MemberTile.onRemove` is wired for real here (see
///   `FamilyMembersRepository`'s doc comment) — the reference leaves it a
///   `// TODO: remove member flow` stub despite `ManagePremiumService.deleteMember`
///   already existing.
struct ManageFamilyMembersView: View {
    @State private var viewModel = ManageFamilyMembersViewModel()
    @State private var isAddMemberSheetPresented = false
    @State private var memberPendingRemoval: FamilyMember?
    @State private var invitePendingCancellation: FamilyInvite?

    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    var body: some View {
        content
            .navigationTitle("Manage Family Members")
            .navigationBarTitleDisplayMode(.inline)
            .background(theme.color(.backgroundPrimary))
            .task { await viewModel.load() }
            .appSheet(isPresented: $isAddMemberSheetPresented) {
                AddMemberSheet(viewModel: viewModel) { toastCenter.show("Invite sent.") }
            }
            .confirmationDialog(
                "Remove \(memberPendingRemoval?.name ?? "this member") from your family plan?",
                isPresented: isPresentingRemoveMemberDialog,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) { confirmRemoveMember() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Cancel this invite?",
                isPresented: isPresentingCancelInviteDialog,
                titleVisibility: .visible
            ) {
                Button("Cancel Invite", role: .destructive) { confirmCancelInvitation() }
                Button("Keep Invite", role: .cancel) {}
            }
    }

    private var isPresentingRemoveMemberDialog: Binding<Bool> {
        Binding(
            get: { memberPendingRemoval != nil },
            set: { if !$0 { memberPendingRemoval = nil } }
        )
    }

    private var isPresentingCancelInviteDialog: Binding<Bool> {
        Binding(
            get: { invitePendingCancellation != nil },
            set: { if !$0 { invitePendingCancellation = nil } }
        )
    }

    private func confirmRemoveMember() {
        guard let member = memberPendingRemoval else { return }
        memberPendingRemoval = nil
        Task {
            let message = await viewModel.removeMember(member)
            toastCenter.show(message)
        }
    }

    private func confirmCancelInvitation() {
        guard let invite = invitePendingCancellation else { return }
        invitePendingCancellation = nil
        Task {
            let message = await viewModel.cancelInvitation(invite)
            toastCenter.show(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            LoadingStateView()
        case let .failed(message):
            ErrorStateView(title: "Something went wrong", message: message) {
                Task { await viewModel.load() }
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let data = viewModel.data {
                    Text("Share Premium with up to \(max(data.maxMembers - 1, 0)) family members.")
                        .typography(Typography.headlineMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    MembersCountChip(current: data.totalMembers, max: data.maxMembers)

                    VStack(spacing: 0) {
                        ForEach(data.members) { member in
                            MemberTile(member: member) { memberPendingRemoval = member }
                        }
                    }

                    if !data.invites.isEmpty {
                        Divider().overlay(theme.color(.separator))

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Invited Members")
                                .typography(Typography.titleMedium)
                                .foregroundStyle(theme.color(.textPrimary))
                                .frame(maxWidth: .infinity, alignment: .leading)

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
                        }
                    }

                    AddMemberButton(isDisabled: data.totalMembers >= data.maxMembers) {
                        isAddMemberSheetPresented = true
                    }
                }
            }
            .padding(Spacing.md)
        }
        .refreshable { await viewModel.refresh() }
    }
}

/// `MemberTile` (Dart). Avatar diameter/corner-radius follow `ProfileView`'s
/// own circular-avatar convention (`diameter / 2`), not `Dimens.userThumbnailSize`
/// literally — no equivalent constant exists natively yet.
private struct MemberTile: View {
    let member: FamilyMember
    let onRemove: () -> Void

    @Environment(\.appTheme) private var theme
    private static let avatarDiameter: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ArtworkView(
                url: ArtworkURLResolver().resolve(
                    path: member.image, variant: .sm, allowedVariants: member.imageVariants
                ),
                width: Self.avatarDiameter,
                height: Self.avatarDiameter,
                cornerRadius: Self.avatarDiameter / 2
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(member.name)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(theme.color(.textPrimary))
                    if member.isOwner {
                        Text("Family Manager")
                            .typography(Typography.labelMedium)
                            .foregroundStyle(theme.color(.textTertiary))
                    }
                }
                Text(member.email)
                    .typography(Typography.labelMedium)
                    .foregroundStyle(theme.color(.textTertiary))
            }

            Spacer()

            if !member.isOwner {
                Button("Remove", action: onRemove)
                    .typography(Typography.labelLarge)
                    .foregroundStyle(theme.color(.statusError))
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

/// `MembersCountChip` (Dart).
private struct MembersCountChip: View {
    let current: Int
    let max: Int

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("\(current) of \(max) Members added")
            .typography(Typography.labelMedium)
            .foregroundStyle(theme.color(.textSecondary))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                Capsule(style: .continuous).fill(theme.color(.surfaceSecondary))
            }
    }
}

/// `AddMemberButton` (Dart) — same dashed-border treatment
/// (`DottedBorder`/`dashPattern: [6, 3]`), drawn with a native dashed
/// `StrokeStyle` instead of a third-party package.
private struct AddMemberButton: View {
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text("Add Member")
                .typography(Typography.titleSmall)
                .foregroundStyle(isDisabled ? theme.color(.textTertiary) : theme.color(.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(
                            isDisabled ? theme.color(.border).opacity(0.5) : theme.color(.border),
                            style: StrokeStyle(lineWidth: 1.2, dash: [6, 3])
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// `InviteTile` (Dart). The avatar is a plain placeholder box with a raw SF
/// Symbol (no `IconToken` case for a bare person glyph exists, and that enum
/// is out of this task's reach) — matching this codebase's own established
/// fallback of using `Image(systemName:)` directly when a token doesn't
/// cover a one-off glyph (see `SettingsView.swift`'s row icons).
private struct InviteTile: View {
    let invite: FamilyInvite
    let onResend: () -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var theme
    private static let avatarDiameter: CGFloat = 44

    private var showsResend: Bool {
        invite.status == "expired" || invite.status == "cancelled"
    }

    private var statusText: String {
        switch invite.status {
        case "pending": "Pending"
        case "expired": "Expired"
        case "cancelled": "Cancelled"
        case "accepted": "Joined"
        default: invite.status
        }
    }

    private var statusColor: Color {
        switch invite.status {
        case "pending": theme.color(.statusWarning)
        case "expired": theme.color(.textTertiary)
        case "cancelled": theme.color(.statusError)
        case "accepted": theme.color(.statusSuccess)
        default: theme.color(.textTertiary)
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(theme.color(.surfaceSecondary))
                .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
                .overlay {
                    Image(systemName: "person")
                        .foregroundStyle(theme.color(.textTertiary))
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(invite.displayText)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                Text(statusText)
                    .typography(Typography.labelMedium)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            HStack(spacing: Spacing.md) {
                if showsResend {
                    Button("Resend", action: onResend)
                        .typography(Typography.labelLarge)
                        .foregroundStyle(theme.color(.statusSuccess))
                }
                Button("Cancel", action: onCancel)
                    .typography(Typography.labelLarge)
                    .foregroundStyle(theme.color(.statusError))
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

/// `showInviteMemberSheet` (Dart). Bare content — no manual chrome/drag
/// handle — `.appSheet` already supplies the glass container and handle
/// (see `VerseOfDayOptionsSheet`'s own doc comment for the same convention).
private struct AddMemberSheet: View {
    let viewModel: ManageFamilyMembersViewModel
    let onSent: () -> Void

    @State private var identifier = ""
    @State private var validationError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Invite a Family Member")
                .typography(Typography.titleLarge)
                .foregroundStyle(theme.color(.textPrimary))
                .multilineTextAlignment(.center)

            Text("Enter an email address or phone number. We'll send them a link to join your Family Plan.")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
                .multilineTextAlignment(.center)

            AppTextField(
                text: $identifier,
                label: "Email or Phone Number",
                placeholder: "Email or Phone Number",
                keyboardType: .emailAddress,
                errorMessage: validationError ?? viewModel.sendInviteErrorMessage
            )

            Text("They must have a Hallelujah account to join.")
                .typography(Typography.bodySmall)
                .foregroundStyle(theme.color(.textTertiary))
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.sm) {
                AppButton.secondary("Cancel") { dismiss() }
                AppButton(label: "Send Invite", action: send, isLoading: viewModel.isSendingInvite)
            }

            Text("Each invite expires in 48 hours.")
                .typography(Typography.labelSmall)
                .foregroundStyle(theme.color(.textTertiary))
        }
        .padding(Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    private func send() {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard ManageFamilyMembersViewModel.isValidIdentifier(trimmed) else {
            validationError = "Please enter a valid email or mobile number"
            return
        }
        validationError = nil
        Task {
            if await viewModel.sendInvitation(identifier: trimmed) {
                onSent()
                dismiss()
            }
        }
    }
}
