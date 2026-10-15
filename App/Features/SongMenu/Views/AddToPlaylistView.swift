import SwiftUI

/// `showAddToPlaylistSheet` / `UserPlaylistListWidget(songId:)`: the
/// listener's own playlists; tapping one attaches the song.
struct AddToPlaylistView: View {
    let viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppButton.secondary("Create New Playlist") {
                coordinator.push(.createPlaylist(userPlaylistID: nil, songType: nil, songID: viewModel.song.id))
                onOutcome(.dismiss)
            }
            .padding(Dimens.paddingSmall)
            .padding(.horizontal, Dimens.paddingSmall)
            content
        }
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
            note("No Playlists Found")
        case .loaded(let playlists):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists) { playlist in
                        row(playlist)
                    }
                }
            }
        }
    }

    /// `_PlaylistSheetTile`: 64pt thumbnail, title, created-at caption, and an
    /// add / remove circle that reflects whether the playlist holds the song.
    private func row(_ playlist: UserPlaylist) -> some View {
        let isAdded = playlist.songIDs.contains(viewModel.song.id)
        return Button {
            Task { onOutcome(await viewModel.toggle(playlist)) }
        } label: {
            HStack(spacing: Dimens.paddingLarge) {
                ArtworkView(
                    url: ArtworkURLResolver().resolve(path: playlist.image, variant: .sm, allowedVariants: playlist.imageVariants),
                    width: 64,
                    height: 64,
                    cornerRadius: Dimens.cornerRadius
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .typography(Typography.bodyLarge)
                        .foregroundStyle(theme.color(.textPrimary))
                        .lineLimit(1)
                    Text(SongMenuViewModel.playlistDateText(playlist.createdAt))
                        .typography(TypographyToken(size: 10, weight: .medium, lineHeightMultiple: 1.2))
                        .foregroundStyle(theme.color(.textSecondary))
                }
                Spacer(minLength: 0)
                Image(systemName: isAdded ? "minus.circle" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.color(.textPrimary))
                    .padding(Dimens.paddingSmall)
            }
            .padding(.horizontal, Dimens.paddingLarge)
            .padding(.vertical, Dimens.spacing4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .typography(Typography.bodyMedium)
            .foregroundStyle(theme.color(.textSecondary))
            .frame(maxWidth: .infinity, minHeight: Spacing.xxl)
    }
}
