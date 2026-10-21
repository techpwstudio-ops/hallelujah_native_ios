import SwiftUI

/// `AppRoute.feedback` — the Help & Support dashboard opened on its Feedback tab.
struct FeedbackView: View {
    var body: some View { HelpView(initialIndex: 1) }
}

/// Ports `FeedbackPage` (`lib/views/support/feedback.dart`): scrolling form
/// (16pt padding) with the reason dropdown, 20pt gap and a required
/// multi-line "Enter description" field, above a sticky bottom bar with
/// Submit (enabled once valid) and a secondary Cancel that pops the screen.
/// The earlier native-only "Email us instead" action is removed: Flutter has
/// no such control.
struct FeedbackContentView: View {
    @State private var viewModel = FeedbackViewModel()
    @State private var selectedReason: SupportDropdown.Item?
    @State private var description = ""

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    /// `reasons` (`feedback.dart`), verbatim. Two submitted `value`s differ
    /// from their labels ("Subscription Issue", "Content Issue").
    private static let reasons: [SupportDropdown.Item] = [
        .init(label: String(localized: "Playback Issue"), value: "Playback Issue"),
        .init(label: String(localized: "Audio Quality Problem"), value: "Audio Quality Problem"),
        .init(label: String(localized: "App Crash / Bug"), value: "App Crash / Bug"),
        .init(label: String(localized: "Subscription / Payment Issue"), value: "Subscription Issue"),
        .init(label: String(localized: "Content Not Available"), value: "Content Issue"),
    ]

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        selectedReason != nil && !trimmedDescription.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SupportDropdown(
                        hint: String(localized: "Choose reason"),
                        items: Self.reasons,
                        selectedValue: selectedReason?.value,
                        isDisabled: viewModel.isSubmitting
                    ) { selectedReason = $0 }

                    Spacer().frame(height: 20)

                    VStack(alignment: .leading, spacing: 0) {
                        ParityRequiredLabel(text: "Enter description")
                            .padding(.bottom, 8)
                        ParityTextField(
                            text: $description,
                            placeholder: "Enter description",
                            enabled: !viewModel.isSubmitting,
                            capitalization: .sentences,
                            axis: .vertical,
                            lineLimit: 1...5
                        )
                    }
                    .padding(.vertical, 2)
                }
                .padding(16)
                // Native-only tablet/Mac adaptation (no Flutter counterpart).
                .readableContentWidth()
            }
            .scrollDismissesKeyboard(.interactively)

            SupportBottomBar {
                SupportCustomButton(text: "Submit", enabled: isValid, isLoading: viewModel.isSubmitting) { submit() }
                SupportCustomButton(text: "Cancel", isSecondary: true) { coordinator.pop() }
            }
        }
    }

    /// `_onSubmit`: success toasts, resets the form and pops; a non-200 shows
    /// the server message (or "Failed"); a thrown error shows "Something went wrong".
    private func submit() {
        guard let selectedReason else {
            toastCenter.show("Please select a reason")
            return
        }
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
}
