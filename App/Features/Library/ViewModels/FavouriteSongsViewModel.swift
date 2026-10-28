import Foundation
import Observation

/// Same shape as `GenreSongsViewModel`'s own private page struct — see its
/// doc comment for why this isn't generalized into one shared type.
private struct FavouriteSongsPage: Sendable {
    var items: [Song] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// Ports `FavouriteSongsScreen` (`lib/views/library/favourite_songs_list.dart`):
/// a gradient header (label, count, Shuffle/Play) plus the paginated
/// "already-favourited" song list. No per-row unfavorite affordance: a
/// direct read of Dart's own row chain (`SongListItem` →
/// `MusicListItem`/`EpisodeListItem` → `MediaTrailingSection`) shows the
/// favourite toggle lives inside the "..." song action sheet
/// (`song_menu_sheet.dart`'s "Add/Remove from favorites" row), not as a
/// direct heart on the row itself — and that sheet doesn't exist anywhere
/// in this app yet (`CreatorSongRow`'s own doc comment already names this
/// same gap). So this list reuses `CreatorSongRow` exactly as every other
/// song list in this app already does, rather than inventing a row-level
/// heart Dart's own screen doesn't actually have.
///
/// `type` arrives from `AppRoute.favouriteSongs(type:label:asset:)` as the
/// raw `String` Dart's own `SongType.name` sends (`"music"`/`"episode"`);
/// `asset` isn't threaded through at all — confirmed by a direct read of
/// `favourite_songs_list.dart`, that field is accepted by the Dart screen's
/// own constructor but never actually referenced in its body (only
/// `LibraryUi`, the quick-link tile one screen up, uses it, for its own
/// icon).
@MainActor
@Observable
final class FavouriteSongsViewModel {
    let label: String
    private let type: HomeContentType

    private var page = FavouriteSongsPage()
    /// Why the first page didn't load ("No internet connection…"). Without it
    /// a failed first page fell through to the empty state and an offline
    /// listener was told they had no liked music.
    private(set) var loadError: String?
    private let repository: any FavouriteRepository
    private let logger = AppLogger(category: .content)

    init(type: String?, label: String, container: DependencyContainer = .current) {
        self.type = type.flatMap(HomeContentType.init(rawValue:)) ?? .all
        self.label = label
        repository = container.resolve()
    }

    var songs: [Song] { page.items }
    var isLoadingSongs: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }
    var songCount: Int { page.items.count }

    /// `QueueAttribution.playerID` needs the same raw type string Dart's
    /// `getPlayerId` builds `playerId = "favourite_${type.name}"` from.
    var attributionID: String { type.rawValue }

    /// `widget.type == SongType.music ? "Music" : "Episodes"` — literal Dart
    /// ternary (`favourite_songs_list.dart`), including its `.all`-falls-to-
    /// "Episodes" edge case (never actually reached: every real call site
    /// sends `music`/`episode`).
    var likedTitle: String {
        type == .music ? String(localized: "Liked Music") : String(localized: "Liked Episodes")
    }

    var countText: String {
        type == .music ? String(localized: "\(songCount) Music") : String(localized: "\(songCount) Episodes")
    }

    var emptyText: String {
        switch type {
        case .music: String(localized: "No music")
        case .episode: String(localized: "No episode")
        default: String(localized: "No \(attributionID)")
        }
    }

    func onAppear() async {
        guard !hasLoadedOnce, !page.isLoading else { return }
        await loadMoreSongs()
    }

    /// `FavouriteSongsChangedEvent`: a like/unlike elsewhere (the player over
    /// this page, the song menu) re-reads page 1 so the list matches.
    func reload() async {
        guard hasLoadedOnce, !page.isLoading else { return }
        page = FavouriteSongsPage()
        await loadMoreSongs()
    }

    func loadMoreSongsIfNeeded(currentItem: Song) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreSongs()
    }

    func loadMoreSongs() async {
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchFavouriteSongs(type: type, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
            loadError = nil
        } catch {
            logger.warning("favourite songs page load failed: \(error)")
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
                let message = UserFacingError.message(for: error)
                loadError = message.isEmpty ? nil : message
            }
        }
        page.isLoading = false
    }
}
