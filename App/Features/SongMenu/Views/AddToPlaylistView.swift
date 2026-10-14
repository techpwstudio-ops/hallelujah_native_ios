import SwiftUI

/// `showAddToPlaylistSheet` / `UserPlaylistListWidget(songId:)`: the
/// listener's own playlists; tapping one attaches the song.
struct AddToPlaylistView: View {
    let viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Add to playlist")
                .typography(Typography.titleLarge)
                .foregroundStyle(theme.color(.textPrimary))
            content
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .task { await viewModel.loadPlaylists() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.playlists {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: Spacing.xxl)
        case .failed:
            note("Couldn't load your playlists.")
        case .loaded(let playlists) where playlists.isEmpty:
            note("You have no playlists yet.")
        case .loaded(let playlists):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists) { playlist in
                        Button {
                            Task { onOutcome(await viewModel.add(to: playlist)) }
                        } label: {
                            Text(playlist.title)
                                .typography(Typography.bodyLarge)
                                .foregroundStyle(theme.color(.textPrimary))
                                .frame(maxWidth: .infinity, minHeight: Spacing.minTapTarget, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isBusy)
                    }
                }
            }
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .typography(Typography.bodyMedium)
            .foregroundStyle(theme.color(.textSecondary))
            .frame(maxWidth: .infinity, minHeight: Spacing.xxl)
    }
}
