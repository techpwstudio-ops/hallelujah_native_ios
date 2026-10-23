import Foundation
import Observation

/// T45's "add songs" picker — the native answer to `content_search_page.dart`'s
/// `isSelect: true` mode (`AddToPlaylistCheckBox`, `SelectContentBloc`), but
/// deliberately not that same screen reused: Dart's picker is the full
/// multi-tab search page (music/episodes/creators/playlists, `_filterTypes`)
/// gated behind a flag; retrofitting that reuse onto `ContentSearchView`/
/// `SearchViewModel` is out of scope here, so this is a separate, smaller
/// view model that searches music and episodes (Flutter's locked `UiItemType.songs` flow).
///
/// Debounce shape copied from `SearchViewModel` (350ms, generation-guarded)
/// but collapsed to one result list instead of four sections and no
/// pagination — `SearchRepository.search` is always sent page 1 for every
/// section, and this picker never needs a "load more" tail.
@MainActor
@Observable
final class AddSongsToPlaylistViewModel {
    private static let debounceMilliseconds = 350

    let playlistID: String

    private let searchRepository: any SearchRepository
    private let userPlaylistRepository: any UserPlaylistRepository
    private let logger = AppLogger(category: .content)

    /// Same staleness guard as `SearchViewModel.generation`: bumped on every
    /// fresh dispatch, a result is only applied if its captured generation
    /// still matches when it lands.
    private var generation = 0
    private var debounceTask: Task<Void, Never>?

    private(set) var searchFieldText = ""
    private(set) var songs: [Song] = []
    private(set) var isSearching = false
    private(set) var selectedSongIDs: Set<String> = []
    private(set) var isSubmitting = false

    init(playlistID: String, container: DependencyContainer = .current) {
        self.playlistID = playlistID
        searchRepository = container.resolve()
        userPlaylistRepository = container.resolve()
    }

    /// Every keystroke — restarts the 350ms debounce, matching
    /// `SearchViewModel.queryChanged`'s `switchMap`-style cancellation.
    func queryChanged(_ text: String) {
        searchFieldText = text
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            generation += 1
            songs = []
            isSearching = false
            return
        }

        generation += 1
        let thisGeneration = generation
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.debounceMilliseconds))
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: trimmed, generation: thisGeneration)
        }
    }

    func toggleSelection(songID: String) {
        if !selectedSongIDs.insert(songID).inserted {
            selectedSongIDs.remove(songID)
        }
    }

    /// Attaches the current selection and returns. No observable error state
    /// to match — same posture as `SearchViewModel`, which never surfaces
    /// one either: a failed attach is logged only, and the caller (the
    /// view's Add button) dismisses either way, leaving the parent's own
    /// post-dismiss refresh to reflect whatever actually landed.
    func submit() async {
        guard !selectedSongIDs.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await userPlaylistRepository.attachSongs(playlistID: playlistID, songIDs: Array(selectedSongIDs))
        } catch {
            logger.warning("attach songs to playlist \(playlistID) failed: \(error)")
        }
    }

    private func performSearch(query: String, generation thisGeneration: Int) async {
        guard thisGeneration == generation else { return }
        isSearching = true
        defer {
            if thisGeneration == generation { isSearching = false }
        }

        // Flutter's add-to-playlist search is the locked `UiItemType.songs`
        // flow: music AND episodes in one list. This used to search music
        // only, so podcasts never showed up and couldn't be added.
        do {
            async let music = search(query: query, filter: .music)
            async let episodes = search(query: query, filter: .episode)
            let (musicResults, episodeResults) = try await (music, episodes)
            guard thisGeneration == generation else { return }
            var seen = Set<String>()
            songs = (musicResults.music.items + episodeResults.episodes.items).filter { seen.insert($0.id).inserted }
        } catch {
            guard thisGeneration == generation else { return }
            logger.warning("song search failed: \(error)")
        }
    }

    private func search(query: String, filter: SearchFilter) async throws -> SearchResults {
        try await searchRepository.search(
            query: query,
            filter: filter,
            musicPage: 1,
            episodePage: 1,
            creatorPage: 1,
            playlistPage: 1,
            userPlaylistId: playlistID
        )
    }
}
