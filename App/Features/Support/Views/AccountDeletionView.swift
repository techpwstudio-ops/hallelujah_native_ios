import SwiftUI

/// `AppRoute.deleteAccount` — the Help & Support dashboard opened on its Delete Account tab.
struct AccountDeletionView: View {
    var body: some View { HelpView(initialIndex: 2) }
}

/// Ports `DeleteAccountPage` (`lib/views/support/delete_account.dart`): reason
/// dropdown (+ "Enter your reason" field for Other), sticky bottom bar with
/// "Delete Account" / secondary "Cancel", then the exact 3-step sequence of
/// `_onDeletePressed`: "Confirm" dialog -> device-auth gate -> "Confirm
/// Delete" type-`Delete` dialog (`showDeleteConfirmationDialog`) -> API call.
/// Dialogs use Flutter's custom blurred-dark card (`ParityConfirmationDialog`
/// and `TypeDeleteDialog`) instead of system alerts.
struct DeleteAccountContentView: View {
    @State private var viewModel = AccountDeletionViewModel()
    @State private var selectedReason: SupportDropdown.Item?
    @State private var otherReasonText = ""

    // Step A.
    @State private var isConfirmIntentPresented = false
    @State private var confirmIntentContinuation: CheckedContinuation<Bool, Never>?

    // Step C.
    @State private var isTypeDeletePresented = false
    @State private var typeDeleteContinuation: CheckedContinuation<Bool, Never>?

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    /// `reasons` (`delete_account.dart`), verbatim; "Other" carries the
    /// lowercase `"other"` sentinel.
    private static let reasons: [SupportDropdown.Item] = [
        .init(label: "Privacy concerns", value: "Privacy concerns"),
        .init(label: "Not useful anymore", value: "Not useful anymore"),
        .init(label: "Too many notifications", value: "Too many notifications"),
        .init(label: "Switching to another app", value: "Switching to another app"),
        .init(label: "Other", value: "other"),
    ]

    private var isOther: Bool { selectedReason?.value == "other" }

    private var trimmedOtherReason: String {
        otherReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        guard selectedReason != nil else { return false }
        return isOther ? !trimmedOtherReason.isEmpty : true
    }

    private var finalReason: String {
        isOther ? trimmedOtherReason : (selectedReason?.value ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SupportDropdown(
                        hint: "Choose reason",
                        items: Self.reasons,
                        selectedValue: selectedReason?.value,
                        isDisabled: viewModel.isDeleting
                    ) { item in
                        selectedReason = item
                        if item.value != "other" { otherReasonText = "" }
                    }

                    Spacer().frame(height: 20)

                    if isOther {
                        VStack(alignment: .leading, spacing: 0) {
                            ParityRequiredLabel(text: "Enter your reason")
                                .padding(.bottom, 8)
                            ParityTextField(
                                text: $otherReasonText,
                                placeholder: "Enter your reason",
                                enabled: !viewModel.isDeleting,
                                capitalization: .sentences,
                                axis: .vertical,
                                lineLimit: 1...4
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)

            SupportBottomBar {
                SupportCustomButton(text: "Delete Account", enabled: isValid, isLoading: viewModel.isDeleting) {
                    Task { await beginDeletionFlow() }
                }
                SupportCustomButton(text: "Cancel", isSecondary: true) { coordinator.pop() }
            }
        }
        .fullScreenCover(isPresented: $isConfirmIntentPresented) {
            ParityConfirmationDialog(
                message: "Are you sure you want to delete all data associated with your ID? This action cannot be undone.",
                onCancel: { resumeConfirmIntent(with: false) },
                onConfirm: { resumeConfirmIntent(with: true) }
            )
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $isTypeDeletePresented) {
            TypeDeleteDialog(
                onCancel: { resumeTypeDelete(with: false) },
                onNext: { resumeTypeDelete(with: true) }
            )
            .presentationBackground(.clear)
        }
    }

    // MARK: Deletion sequence (`_onDeletePressed`)

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
        isConfirmIntentPresented = false
        confirmIntentContinuation?.resume(returning: result)
        confirmIntentContinuation = nil
    }

    private func presentTypeDeleteAlert() async -> Bool {
        await withCheckedContinuation { continuation in
            typeDeleteContinuation = continuation
            isTypeDeletePresented = true
        }
    }

    private func resumeTypeDelete(with result: Bool) {
        isTypeDeletePresented = false
        typeDeleteContinuation?.resume(returning: result)
        typeDeleteContinuation = nil
    }
}

/// `showDeleteConfirmationDialog` (`lib/dialogs/confirmation_dialog.dart`):
/// 72% scrim, 28pt card, 64pt trash badge, "Confirm Delete", hint copy, an
/// autofocused "Type Delete" field and Cancel | Next (Next enabled only when
/// the text trims to exactly "Delete"). Not dismissible by tapping outside.
private struct TypeDeleteDialog: View {
    let onCancel: () -> Void
    let onNext: () -> Void

    @State private var text = ""
    @State private var shown = false
    @FocusState private var focused: Bool

    private var canDelete: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == "Delete"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer().frame(height: 22)
                ZStack {
                    Circle().fill(Color.white.opacity(0.06))
                    Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    Image(systemName: "trash")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 64, height: 64)
                Spacer().frame(height: 16)
                Text("Confirm Delete")
                    .font(AccountParity.font(22, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.white)
                Spacer().frame(height: 8)
                Text("To continue, type 'Delete' exactly in the field below.")
                    .font(AccountParity.font(14.5))
                    .lineSpacing(14.5 * 0.45)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer().frame(height: 20)
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Type Delete")
                            .font(AccountParity.font(15))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $text)
                        .font(AccountParity.font(16, .medium))
                        .foregroundStyle(Color.white)
                        .tint(Color.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 0.18 : 0.08), lineWidth: focused ? 1.2 : 1)
                )
                .padding(.horizontal, 20)
                Spacer().frame(height: 22)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(AccountParity.font(17, .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                    Button(action: onNext) {
                        Text("Next")
                            .font(AccountParity.font(17, .bold))
                            .foregroundStyle(canDelete ? Color.white : Color.white.opacity(0.28))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete)
                }
                .frame(height: 58)
            }
            .frame(maxWidth: 430)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AccountParity.sheetBackground.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 16)
            .padding(.horizontal, 22)
            .scaleEffect(shown ? 1 : 0.95)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) { shown = true }
            focused = true
        }
    }
}
