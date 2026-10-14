import Foundation
import Observation

/// One paged fetch of a genre's songs. Same shape as
/// `CreatorProfileViewModel`'s `CreatorContentPage<Item>`, just not generic
/// over a tab key — a genre has exactly one list, not four tabs.
private struct GenreSongsPage: Sendable {
    var items: [Song] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// Ports `GenreSongs` (`lib/views/search/category_songs.dart`): a genre's
/// header (hero image, name, Shuffle, Play/Pause) plus its paginated song
/// list.
///
/// `AppRoute.genreSongs` (T42) now carries the pushing screen's already-
/// loaded genre name/image inline — mirroring `CategoryUI.onTap`
/// (`category_ui.dart`), which passes the whole `Genre` object through Dart's
/// own navigation call, since the backend has no single-genre detail
/// endpoint to re-fetch one by id from (`genre.controller.js` exports only
/// `getGenres`/`getGenreSongs`, confirmed directly). Songs still need their
/// own paginated fetch — `/genre/songs/:genreId` — independent of that.
@MainActor
@Observable
final class GenreSongsViewModel {
    let genreID: String?
    private(set) var genreName: String?
    private(set) var genreImage: String?
    private(set) var genreImageVariants: String?

    private var page = GenreSongsPage()
    private let repository: any GenreRepository
    private let logger = AppLogger(category: .content)

    init(
        genreID: String?,
        genreName: String?,
        genreImage: String?,
        genreImageVariants: String?,
        container: DependencyContainer = .current
    ) {
        self.genreID = genreID
        self.genreName = genreName
        self.genreImage = genreImage
        self.genreImageVariants = genreImageVariants
        repository = container.resolve()
    }

    var songs: [Song] { page.items }
    var isLoadingSongs: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }

    func onAppear() async {
        guard !hasLoadedOnce, !page.isLoading else { return }
        await loadMoreSongs()
    }

    func loadMoreSongsIfNeeded(currentItem: Song) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreSongs()
    }

    func loadMoreSongs() async {
        guard let genreID else {
            // No id to fetch with (shouldn't happen in practice — BrowseView only
            // sources genres with real ids — but without this, `hasLoadedOnce` would
            // never flip true and the screen would stay permanently blank: no
            // spinner, no empty state, no retry).
            page.page = 1
            page.hasMore = false
            return
        }
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchSongs(genreID: genreID, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
        } catch {
            logger.warning("genre songs page load failed: \(error)")
            // First page failed with no data to show yet: mark it attempted
            // so the view can fall through to an empty state rather than
            // spinning forever (`page.page` starting at 0 means `hasLoadedOnce`
            // would otherwise never flip true).
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
            }
        }
        page.isLoading = false
    }
}
