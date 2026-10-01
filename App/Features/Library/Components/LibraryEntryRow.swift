import SwiftUI

/// Ports `LibraryListItem`'s row rendering (`lib/widgets/playlists/
/// library_list_item.dart`) for the merged list's non-`userPlaylist` rows —
/// `_SavedItemRow`: a 56×56 thumbnail, title, and a subtitle of
/// `"Album"`/`"Season"` (creator-owned only) or `"Playlist"` (company-owned,
/// or a creator-owned entry that's neither), joined with `" • "` + creator
/// name when one is present.
///
/// `userPlaylist` rows get a lighter-weight subtitle here rather than
/// porting Dart's separate `UserPlaylistListItem` (its own menu/visibility-
/// badge widget) — that's T45 territory (User playlists CRUD), which this
/// task doesn't build; tapping still navigates to `AppRoute
/// .userPlaylistSongs`, a placeholder destination until then.
///
/// Long-press "⋮" content menu (share/library/add-to-queue) is a deliberate
/// scope cut, same reasoning as `GenreSongsView`'s own doc comment: it needs
/// `QueueSourceService`-equivalent infrastructure this app doesn't have
/// anywhere yet.
struct LibraryEntryRow: View {
    let entry: LibraryEntry
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let thumbnailSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                ArtworkView(url: resolvedArtwork, width: Self.thumbnailSize, height: Self.thumbnailSize)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(theme.color(.textPrimary))
                        .lineLimit(1)
                    Text(subtitle)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private var resolvedArtwork: URL? {
        switch entry {
        case let .playlist(playlist):
            return ArtworkURLResolver().resolve(path: playlist.image, variant: .sm, allowedVariants: playlist.imageVariants)
        case let .userPlaylist(_, _, image, imageVariants, _, _):
            return ArtworkURLResolver().resolve(path: image, variant: .sm, allowedVariants: imageVariants)
        }
    }

    private var title: String {
        switch entry {
        case let .playlist(playlist):
            return playlist.title.isEmpty ? "Untitled Playlist" : playlist.title
        case let .userPlaylist(_, title, _, _, _, _):
            return title.isEmpty ? "Untitled Playlist" : title
        }
    }

    private var subtitle: String {
        switch entry {
        case let .playlist(playlist):
            let kind = self.kind(for: playlist)
            if case let .creator(_, name) = playlist.owner, let name, !name.isEmpty {
                return "\(kind) • \(name)"
            }
            return kind
        case let .userPlaylist(_, _, _, _, songsCount, _):
            guard let songsCount else { return "Playlist" }
            return "\(songsCount) Songs"
        }
    }

    /// Creator-owned is always "Album" or "Season" — `Playlist.isSeason`/
    /// `.isAlbum` are a strict binary complement of each other (T43; see
    /// `Playlist.swift`'s doc comment), matching `_SavedItemRow._resolve()`'s
    /// own `isSeason ? 'Season' : 'Album'`, never a third "neither" case.
    private func kind(for playlist: Playlist) -> String {
        switch playlist.owner {
        case .company:
            return "Playlist"
        case .creator:
            return playlist.isSeason ? "Season" : "Album"
        }
    }
}
