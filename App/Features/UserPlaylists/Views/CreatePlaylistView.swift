import SwiftUI

/// Ports `CreatePlaylistPage` (`lib/views/library/create_playlist.dart`):
/// one heading, one text field, one submit button — structural only, not
/// pixel parity (D10's pixel-parity rule is scoped to the splash/auth
/// screens, not Library), so this uses `AppTextField`/`AppButton` rather
/// than Dart's raw `TextField`/`FilledButton` and drops its circular icon
/// and gradient background.
struct CreatePlaylistView: View {
    @State private var viewModel: CreatePlaylistViewModel
    @State private var title = ""

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    init(userPlaylistID: String?, songID: String?) {
        _viewModel = State(initialValue: CreatePlaylistViewModel(userPlaylistID: userPlaylistID, songID: songID))
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if viewModel.isLoadingExisting {
                LoadingStateView()
            } else {
                form
            }
        }
        .background(theme.color(.backgroundPrimary))
        .task {
            guard let existingTitle = await viewModel.loadExistingTitle() else { return }
            title = existingTitle
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(viewModel.isEditing ? "Rename playlist" : "Name your playlist")
                .typography(Typography.headlineMedium)
                .foregroundStyle(theme.color(.textPrimary))

            AppTextField(
                text: $title,
                placeholder: "My playlist",
                errorMessage: viewModel.errorMessage,
                enabled: !viewModel.isSubmitting
            )
            .onSubmit { Task { await submit() } }

            AppButton(
                label: viewModel.isEditing ? "Save changes" : "Create playlist",
                action: { Task { await submit() } },
                isLoading: viewModel.isSubmitting,
                enabled: canSubmit
            )
        }
        .padding(Spacing.md)
    }

    /// `_submit` — pop THEN push, in that order, on either a create or a
    /// rename success; a failure leaves this screen up with
    /// `viewModel.errorMessage` now set.
    private func submit() async {
        guard let result = await viewModel.submit(title: title) else { return }
        coordinator.pop()
        coordinator.push(.userPlaylistSongs(playlistID: result.id))
    }
}
