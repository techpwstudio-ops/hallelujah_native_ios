import SwiftUI

/// Ports `FeedbackPage` (`lib/views/support/feedback.dart`): a reason
/// dropdown, a required free-text description, and a Submit button that
/// posts both as `{title, description}`. Structural only, not pixel parity
/// (D10's pixel-parity rule is scoped to the splash/auth screens), so this
/// reuses `AppButton`/the app's own field-styling conventions rather than
/// Dart's `dropDownInput`/`textInput` — same posture `CreatePlaylistView`
/// already takes on its own form.
///
/// One native-only addition with no Dart or backend precedent: an "Email us
/// instead" fallback action (T71's roadmap explicitly asks for one on this
/// screen specifically). See `supportEmailAddress` below.
struct FeedbackView: View {
    @State private var viewModel = FeedbackViewModel()
    @State private var selectedReason: FeedbackReason?
    @State private var description = ""

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    /// `reasons` (`feedback.dart`), copied verbatim. Two entries' submitted
    /// `value` deliberately differs from the `label` shown to the user:
    /// "Subscription / Payment Issue" -> "Subscription Issue" and
    /// "Content Not Available" -> "Content Issue".
    private static let reasons: [FeedbackReason] = [
        FeedbackReason(label: "Playback Issue", value: "Playback Issue"),
        FeedbackReason(label: "Audio Quality Problem", value: "Audio Quality Problem"),
        FeedbackReason(label: "App Crash / Bug", value: "App Crash / Bug"),
        FeedbackReason(label: "Subscription / Payment Issue", value: "Subscription Issue"),
        FeedbackReason(label: "Content Not Available", value: "Content Issue"),
    ]

    /// No real support-contact address exists anywhere in the Flutter app or
    /// backend source (confirmed by exhaustive prior grounding) — this is a
    /// placeholder standing in for one until a real address is available.
    private let supportEmailAddress = "support@example.com" // PLACEHOLDER — no real support email address exists in either the Flutter app or backend source; replace with a real address before shipping.

    /// `isValid` (`feedback.dart`).
    private var isValid: Bool {
        selectedReason != nil && !trimmedDescription.isEmpty
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                reasonField
                descriptionField

                AppButton(
                    label: "Submit",
                    action: { submit() },
                    isLoading: viewModel.isSubmitting,
                    enabled: isValid
                )

                AppButton.ghost("Email us instead", leadingIcon: .mail) { openSupportEmail() }
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
        .navigationTitle("Feedback")
    }

    // MARK: - Reason

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Reason")
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.textPrimary))

            Menu {
                ForEach(Self.reasons) { reason in
                    Button(reason.label) { selectedReason = reason }
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
            .disabled(viewModel.isSubmitting)
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Description")
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.textPrimary))

            ZStack(alignment: .topLeading) {
                if description.isEmpty {
                    Text("Enter description")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textTertiary))
                        .padding(.horizontal, Spacing.sm + 4)
                        .padding(.vertical, Spacing.sm + 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $description)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 140)
                    .disabled(viewModel.isSubmitting)
            }
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(theme.color(.surfaceInput))
            }
        }
    }

    // MARK: - Actions

    /// `_onSubmit` — on success, resets the form and pops
    /// (`NavigationService.back()`); on a non-200 response, shows the
    /// server's own message and leaves the form up for a retry; on a
    /// transport failure, shows Dart's fixed catch-block string. Only the
    /// success toast is a fixed client-side string rather than the server's
    /// own — see `SubmitFeedbackResult`'s doc comment.
    private func submit() {
        guard let selectedReason else { return }
        let trimmed = trimmedDescription
        guard !trimmed.isEmpty else { return }

        Task {
            guard let outcome = await viewModel.submit(title: selectedReason.value, description: trimmed) else { return }
            switch outcome {
            case .success:
                toastCenter.show("Feedback submitted successfully")
                description = ""
                self.selectedReason = nil
                coordinator.pop()
            case let .failure(message):
                toastCenter.show(message ?? "Failed")
            case .transportError:
                toastCenter.show("Something went wrong")
            }
        }
    }

    /// Opens a `mailto:` link pre-filled with a subject — `UIApplication
    /// .shared.open(url)`, the same external-URL-handoff call
    /// `SplashView`'s update alert already uses.
    private func openSupportEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmailAddress
        components.queryItems = [URLQueryItem(name: "subject", value: "Hallelujah App Feedback")]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

/// A selectable feedback reason: the `label` shown to the user and the
/// `value` submitted as `title` — see `FeedbackView.reasons`'s doc comment
/// for the two entries where they intentionally differ.
private struct FeedbackReason: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { value }
}
