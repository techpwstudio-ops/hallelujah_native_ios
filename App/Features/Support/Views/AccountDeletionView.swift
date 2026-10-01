import SwiftUI

/// Ports `DeleteAccountPage` (`lib/views/support/delete_account.dart`): a
/// reason dropdown (with a required free-text field for "Other"), then a
/// three-step confirmation sequence — "are you sure", a device-auth gate,
/// "type Delete exactly" — before the actual API call. Structural only, not
/// pixel parity (D10 is scoped to the splash/auth screens), same posture
/// `FeedbackView` already takes for its own dropdown/field styling.
///
/// This is a destructive, irreversible-feeling flow, so every step below —
/// including the abort-silently-with-no-toast behavior on a cancelled step —
/// is grounded directly in `_onDeletePressed`, `showConfirmationDialog`, and
/// `showDeleteConfirmationDialog`, not simplified or reordered. The backend
/// itself actually schedules deletion 7 days out rather than deleting
/// synchronously, but Dart's own UI never surfaces that grace period either
/// (just this same toast + sign-out), so none is added here — that would be
/// scope beyond this port, not a correction of one.
struct AccountDeletionView: View {
    @State private var viewModel = AccountDeletionViewModel()
    @State private var selectedReason: AccountDeletionReason?
    @State private var otherReasonText = ""

    // Step A — "are you sure" alert. Bridged to `async`/`await` with a stored
    // continuation (same shape as `checkBiometricGate`'s LAContext bridge)
    // so `beginDeletionFlow()` below can read the whole 3-step sequence as
    // one straight-line function instead of a chain of completion handlers.
    @State private var isConfirmIntentPresented = false
    @State private var confirmIntentContinuation: CheckedContinuation<Bool, Never>?

    // Step C — "type Delete exactly" alert.
    @State private var isTypeDeletePresented = false
    @State private var typeDeleteText = ""
    @State private var typeDeleteContinuation: CheckedContinuation<Bool, Never>?

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    /// `reasons` (`delete_account.dart`), copied verbatim — "Other"'s value
    /// is the lowercase `"other"` sentinel `isOther` checks against; every
    /// other entry's value equals its label exactly.
    private static let reasons: [AccountDeletionReason] = [
        AccountDeletionReason(label: "Privacy concerns", value: "Privacy concerns"),
        AccountDeletionReason(label: "Not useful anymore", value: "Not useful anymore"),
        AccountDeletionReason(label: "Too many notifications", value: "Too many notifications"),
        AccountDeletionReason(label: "Switching to another app", value: "Switching to another app"),
        AccountDeletionReason(label: "Other", value: "other"),
    ]

    /// `isOther` (`delete_account.dart`).
    private var isOther: Bool { selectedReason?.value == "other" }

    /// `isValid` (`delete_account.dart`).
    private var isValid: Bool {
        guard selectedReason != nil else { return false }
        return isOther ? !trimmedOtherReason.isEmpty : true
    }

    private var trimmedOtherReason: String {
        otherReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `finalReason` (`_onDeletePressed`).
    private var finalReason: String {
        isOther ? trimmedOtherReason : (selectedReason?.value ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                reasonField
                if isOther {
                    otherReasonField
                }
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
        .safeAreaInset(edge: .bottom) {
            actionButtons
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(theme.color(.backgroundPrimary))
        }
        // Step A.
        .alert("Confirm", isPresented: $isConfirmIntentPresented) {
            Button("Cancel", role: .cancel) { resumeConfirmIntent(with: false) }
            Button("Yes") { resumeConfirmIntent(with: true) }
        } message: {
            Text("Are you sure you want to delete all data associated with your ID? This action cannot be undone.")
        }
        // Step C.
        .alert("Confirm Delete", isPresented: $isTypeDeletePresented) {
            TextField("Type Delete", text: $typeDeleteText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { resumeTypeDelete(with: false) }
            Button("Next") { resumeTypeDelete(with: true) }
                .disabled(typeDeleteText.trimmingCharacters(in: .whitespacesAndNewlines) != "Delete")
        } message: {
            Text("To continue, type 'Delete' exactly in the field below.")
        }
    }

    // MARK: - Reason

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Reason")
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.textPrimary))

            Menu {
                ForEach(Self.reasons) { reason in
                    Button(reason.label) { selectReason(reason) }
                }
            } label: {
                HStack {
                    Text(selectedReason?.label ?? "Choose reason")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(selectedReason == nil ? theme.color(.textTertiary) : theme.color(.textPrimary))
                    Spacer(minLength: 0)
                    theme.icon(.chevronDown)
                        .foregroundStyle(theme.color(.textTertiary))
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: Spacing.inputHeight)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(theme.color(.surfaceInput))
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isDeleting)
        }
    }

    /// `updateUI` (`delete_account.dart`) — clears the free-text field when
    /// switching away from "Other".
    private func selectReason(_ reason: AccountDeletionReason) {
        selectedReason = reason
        if reason.value != "other" {
            otherReasonText = ""
        }
    }

    /// `textInput(key: "reason", hint: "Enter your reason", maxLines: 4, ...)`
    /// (`delete_account.dart`) — a multi-line field, so this mirrors
    /// `FeedbackView.descriptionField`'s `TextEditor`-based shape (`AppTextField`
    /// is single-line only) rather than that component, same reasoning
    /// `FeedbackView` already applied to its own free-text field.
    private var otherReasonField: some View {
        ZStack(alignment: .topLeading) {
            if otherReasonText.isEmpty {
                Text("Enter your reason")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textTertiary))
                    .padding(.horizontal, Spacing.sm + 4)
                    .padding(.vertical, Spacing.sm + 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $otherReasonText)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .frame(minHeight: 100)
                .disabled(viewModel.isDeleting)
        }
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.color(.surfaceInput))
        }
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            AppButton(
                label: "Delete Account",
                action: { Task { await beginDeletionFlow() } },
                isLoading: viewModel.isDeleting,
                enabled: isValid
            )
            AppButton.secondary("Cancel", enabled: !viewModel.isDeleting) { coordinator.pop() }
        }
    }

    // MARK: - Deletion sequence

    /// The exact 3-step-then-API sequence `_onDeletePressed` runs, in the
    /// exact same order: confirm intent (Step A) -> device-auth gate (Step
    /// B) -> type "Delete" (Step C) -> the network call (Step D). Any step
    /// that's cancelled or blocked returns early with no toast and no
    /// further action, matching Dart's own silent-abort `.then((v) { if (v)
    /// {...} })`/early-`return false` chain exactly.
    private func beginDeletionFlow() async {
        guard isValid else { return }
        let reason = finalReason

        guard await presentConfirmIntentAlert() else { return }

        switch await viewModel.checkBiometricGate() {
        case let .passed(toastMessage):
            if let toastMessage { toastCenter.show(toastMessage) }
        case .blocked:
            return
        }

        guard await presentTypeDeleteAlert() else { return }

        guard let outcome = await viewModel.deleteAccount(reason: reason) else { return }
        switch outcome {
        case let .response(_, message):
            // Shown unconditionally either way, matching AuthBloc.delete's
            // own unconditional showSnackBarToast BEFORE its status-code
            // check. On success the repository already signed the user out;
            // SignOutSignal-driven RootView redirect takes it from here. On
            // failure (e.g. a deletion already scheduled), the toast alone
            // is the whole story — the user just stays on this screen.
            toastCenter.show(message)
        case .transportError:
            toastCenter.show("Internet error, please check your internet")
        }
    }

    private func presentConfirmIntentAlert() async -> Bool {
        await withCheckedContinuation { continuation in
            confirmIntentContinuation = continuation
            isConfirmIntentPresented = true
        }
    }

    private func resumeConfirmIntent(with result: Bool) {
        confirmIntentContinuation?.resume(returning: result)
        confirmIntentContinuation = nil
    }

    private func presentTypeDeleteAlert() async -> Bool {
        typeDeleteText = ""
        return await withCheckedContinuation { continuation in
            typeDeleteContinuation = continuation
            isTypeDeletePresented = true
        }
    }

    private func resumeTypeDelete(with result: Bool) {
        typeDeleteContinuation?.resume(returning: result)
        typeDeleteContinuation = nil
        typeDeleteText = ""
    }
}

/// A selectable deletion reason: the `label` shown to the user and the
/// `value` this screen either submits directly or checks against the
/// `"other"` sentinel — see `AccountDeletionView.reasons`'s doc comment.
private struct AccountDeletionReason: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { value }
}
