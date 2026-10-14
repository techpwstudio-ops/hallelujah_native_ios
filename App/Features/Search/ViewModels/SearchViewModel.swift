import Foundation
import Observation

/// T40/T41 — ports `SearchBloc`/`SearchState` (`lib/blocs/search/bloc.dart`,
/// `lib/blocs/search/state.dart`) plus the widget-level pending flag
/// `ContentSearchPage` layers on top of it (`content_search_page.dart`).
///
/// Two text properties, on purpose, mirroring two distinct Dart layers
/// collapsed into one Swift type:
/// - `searchFieldText` is the live `TextField` value, updated on every
///   keystroke — Dart's own `TextEditingController` value.
/// - `query` is the committed value a search actually ran against — Dart's
///   `state.query`, which only changes once the bloc's `debounceTime(350)`
///   (`bloc.dart`, the query-changed transformer) elapses and the handler
///   starts running.
/// `isSearchPending` (below) is the gap between them — Dart's own
/// `isSearchPending = query.length >= _kMinQueryLength && state.query !=
/// query` (`content_search_page.dart`), which is why the shimmer appears
/// the instant a keystroke lands, not 350ms later.
@MainActor
@Observable
final class SearchViewModel {
    /// `_kMinQueryLength` (`content_search_page.dart`) — below this, Dart
    /// shows the recent-searches list instead of dispatching anything.
    static let minQueryLength = 1
    private static let debounceMilliseconds = 350
    /// `_kOverviewPreviewCount`-equivalent: how many rows an overview-mode
    /// section shows before "See all". The server always returns a full
    /// page per section (`SearchRepository.search`'s own doc comment) —
    /// this is a client-side `.prefix`, not a smaller page size requested
    /// from the server, matching Dart's own overview widgets doing the same
    /// truncation over a fully-fetched page.
    static let overviewPreviewCount = 5

    private let repository: any SearchRepository
    let recentSearchStore: RecentSearchStore
    private let logger = AppLogger(category: .content)

    /// Bumped on every fresh dispatch (debounced search, filter change,
    /// load-more, clear); a result is only written back if its captured
    /// generation still matches when it completes. Same staleness-guard
    /// shape as `HomeFeedViewModel.generation` — see that type for the
    /// precedent.
    private var generation = 0
    private var debounceTask: Task<Void, Never>?

    private(set) var searchFieldText = ""
    private(set) var query = ""
    private(set) var activeFilter: SearchFilter?

    private(set) var topResult: SearchTopResultItem?
    private(set) var musicPage: Paginated<Song> = .empty
    private(set) var episodePage: Paginated<Song> = .empty
    private(set) var creatorPage: Paginated<SearchCreatorResult> = .empty
    private(set) var playlistPage: Paginated<SearchPlaylistResult> = .empty

    /// The first page of a fresh query/filter — full-screen shimmer.
    private(set) var isInitialLoading = false
    /// A pagination fetch on an already-visible list — no visible spinner,
    /// matching `SectionDetailView`'s own silent-append precedent.
    private(set) var isLoadingMore = false

    /// No observable `error` property: `state.error` is set in Dart
    /// (`bloc.dart`) but never read by any widget in
    /// `content_search_page.dart` — a failed search there just leaves
    /// whatever page was already on screen (or the empty state) up, with no
    /// distinct error UI. Matching that actual behavior rather than
    /// inventing a nicer one Dart doesn't have: failures are logged only.

    /// A locked entry point (`GenreSearchPage` always searches `music`) keeps
    /// this filter through a clear instead of resetting to the "All" overview.
    private let lockedFilter: SearchFilter?

    init(lockedFilter: SearchFilter? = nil, container: DependencyContainer = .current) {
        self.lockedFilter = lockedFilter
        repository = container.resolve()
        recentSearchStore = container.resolve()
        activeFilter = lockedFilter
    }

    /// True the instant a keystroke makes `searchFieldText` diverge from the
    /// last-committed `query` — covers the pre-debounce gap `isInitialLoading`
    /// alone would miss. See the type doc comment.
    var isSearchPending: Bool {
        let trimmed = searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= Self.minQueryLength && trimmed != query
    }

    var isBusy: Bool { isSearchPending || isInitialLoading }

    var isOverview: Bool { activeFilter == nil }

    var hasAnyResults: Bool {
        switch activeFilter {
        case nil:
            topResult != nil
                || !musicPage.items.isEmpty
                || !episodePage.items.isEmpty
                || !creatorPage.items.isEmpty
                || !playlistPage.items.isEmpty
        case .music: !musicPage.items.isEmpty
        case .episode: !episodePage.items.isEmpty
        case .creator: !creatorPage.items.isEmpty
        case .playlists: !playlistPage.items.isEmpty
        }
    }

    /// Overview mode never paginates — `SearchRepository.search` always
    /// fetches page 1 of all four sections there; only a filtered single
    /// section has a "load more" tail. Matches T41's per-tab infinite-scroll
    /// scope.
    var hasMoreData: Bool {
        switch activeFilter {
        case nil: false
        case .music: musicPage.hasMore
        case .episode: episodePage.hasMore
        case .creator: creatorPage.hasMore
        case .playlists: playlistPage.hasMore
        }
    }

    // MARK: - Intents

    /// Every keystroke. Updates the live text immediately (so the field
    /// itself never lags), then restarts the 350ms debounce — a fresh
    /// keystroke cancels whatever debounce was already in flight, matching
    /// rxdart's `switchMap` semantics in `bloc.dart`.
    func queryChanged(_ text: String) {
        searchFieldText = text
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minQueryLength else {
            performClear()
            return
        }

        generation += 1
        let thisGeneration = generation
        let filter = activeFilter
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.debounceMilliseconds))
            guard !Task.isCancelled else { return }
            await self?.performSearch(isFirstPage: true, filter: filter, query: trimmed, generation: thisGeneration)
        }
    }

    /// A filter chip tap. Reads the already-committed `query`, not the live
    /// `searchFieldText` — matching `bloc.dart`'s `_onFilterChanged`, which
    /// reads `state.query` rather than anything widget-level. This also
    /// reproduces a minor Dart timing quirk for free: tapping a chip during
    /// an active debounce window dispatches against the stale committed
    /// query, not whatever's mid-keystroke in the field.
    func selectFilter(_ filter: SearchFilter?) {
        guard !query.isEmpty else { return }
        activeFilter = filter
        debounceTask?.cancel()

        generation += 1
        let thisGeneration = generation
        let committedQuery = query
        Task { await performSearch(isFirstPage: true, filter: filter, query: committedQuery, generation: thisGeneration) }
    }

    /// The active section's pagination trigger, called from `.onAppear` near
    /// the end of a list — see `SectionDetailView`'s identical idiom.
    ///
    /// Also bumps `generation`, unlike a first read of `SectionDetailView`
    /// might suggest is necessary: `.onAppear` fires for the last *two* rows
    /// (not just the last one), so two `loadMore()` calls can land back to
    /// back, synchronously, before either's `Task` has run — without its own
    /// bump, both would capture the same `generation` and neither could tell
    /// the other apart once both `Task`s actually start (Swift never runs a
    /// `Task`'s body inline), letting them race on `musicPage.page`/friends.
    /// Bumping here means the earlier of the two always loses to the later
    /// one's fresher generation the moment its `performSearch` guard runs,
    /// before it ever touches `isLoadingMore` or the network.
    func loadMore() {
        guard !isOverview, !isLoadingMore, hasMoreData, !query.isEmpty else { return }
        generation += 1
        let thisGeneration = generation
        let filter = activeFilter
        let committedQuery = query
        Task { await performSearch(isFirstPage: false, filter: filter, query: committedQuery, generation: thisGeneration) }
    }

    /// The field's ✕ button, and typing back down to empty. Resets
    /// `activeFilter` to `nil` too — matches Dart's `SearchState.initial()`
    /// (a full reset, not just an emptied query), since the widget's own
    /// filter is otherwise always `nil` for the plain (non-picker) search
    /// screen this ports.
    func clearButtonTapped() {
        searchFieldText = ""
        performClear()
    }

    func recordSongTap(_ song: Song) {
        recentSearchStore.record(.song(RecentSongSnapshot(song: song)))
    }

    func recordCreatorTap(_ creator: SearchCreatorResult) {
        recentSearchStore.record(.creator(creator))
    }

    func recordPlaylistTap(_ playlist: SearchPlaylistResult) {
        recentSearchStore.record(.playlist(playlist))
    }

    // MARK: - Private

    private func performClear() {
        debounceTask?.cancel()
        generation += 1
        query = ""
        activeFilter = lockedFilter
        topResult = nil
        musicPage = .empty
        episodePage = .empty
        creatorPage = .empty
        playlistPage = .empty
        isInitialLoading = false
        isLoadingMore = false
    }

    private func performSearch(isFirstPage: Bool, filter: SearchFilter?, query: String, generation thisGeneration: Int) async {
        guard thisGeneration == generation else { return }
        // Committed the moment dispatch starts, before the network await —
        // matches Dart's own handler writing `state.query` synchronously at
        // handler-entry, which is what makes `isSearchPending` above flip
        // false immediately rather than only after the response lands.
        self.query = query
        if isFirstPage {
            isInitialLoading = true
        } else {
            isLoadingMore = true
        }

        defer {
            if thisGeneration == generation {
                isInitialLoading = false
                isLoadingMore = false
            }
        }

        do {
            let results = try await repository.search(
                query: query,
                filter: filter,
                musicPage: pageNumber(for: musicPage, isActive: filter == nil || filter == .music, isFirstPage: isFirstPage),
                episodePage: pageNumber(for: episodePage, isActive: filter == nil || filter == .episode, isFirstPage: isFirstPage),
                creatorPage: pageNumber(for: creatorPage, isActive: filter == nil || filter == .creator, isFirstPage: isFirstPage),
                playlistPage: pageNumber(for: playlistPage, isActive: filter == nil || filter == .playlists, isFirstPage: isFirstPage),
                userPlaylistId: nil
            )
            guard thisGeneration == generation else { return }
            apply(results: results, filter: filter, isFirstPage: isFirstPage)
        } catch {
            guard thisGeneration == generation else { return }
            logger.warning("Search failed: \(error)")
        }
    }

    /// Every section is always sent (`SearchRepository.search`'s own doc
    /// comment), but only the *active* section's page number should ever
    /// advance — the other three keep requesting their already-satisfied
    /// current page, matching `Endpoint.search`'s request shape.
    private func pageNumber<Item: Sendable>(for page: Paginated<Item>, isActive: Bool, isFirstPage: Bool) -> Int {
        guard isActive else { return page.page }
        return isFirstPage ? 1 : page.page + 1
    }

    private func apply(results: SearchResults, filter: SearchFilter?, isFirstPage: Bool) {
        // `topResult` only updates in overview mode — a filtered fetch has
        // no top-result concept in Dart, and clearing it on every filtered
        // page would blank a card the user hasn't asked to move away from.
        if filter == nil {
            topResult = results.topResult
        }

        if filter == nil || filter == .music {
            musicPage = merged(current: musicPage, incoming: results.music, isFirstPage: isFirstPage, key: \.id)
        }
        if filter == nil || filter == .episode {
            episodePage = merged(current: episodePage, incoming: results.episodes, isFirstPage: isFirstPage, key: \.id)
        }
        if filter == nil || filter == .creator {
            creatorPage = merged(current: creatorPage, incoming: results.creators, isFirstPage: isFirstPage, key: \.id)
        }
        if filter == nil || filter == .playlists {
            // Keyed on `compositeID`, not `.id`: a user playlist and a
            // company playlist can share the same raw `id`
            // (`SearchPlaylistResult`'s own doc comment) — de-duping on
            // `.id` alone would silently drop one of them on page append.
            playlistPage = merged(current: playlistPage, incoming: results.playlists, isFirstPage: isFirstPage, key: \.compositeID)
        }
    }

    /// First page replaces outright; a later page appends with de-dup keyed
    /// by whatever the caller says uniquely identifies an item — generic
    /// over a caller-supplied key rather than a blanket `Identifiable`-keyed
    /// helper, specifically so playlists can key on `compositeID` instead of
    /// `id`. See `apply(results:filter:isFirstPage:)`.
    private func merged<Item: Sendable>(
        current: Paginated<Item>,
        incoming: Paginated<Item>,
        isFirstPage: Bool,
        key: (Item) -> String
    ) -> Paginated<Item> {
        guard !isFirstPage else { return incoming }
        var seen = Set(current.items.map(key))
        let appended = current.items + incoming.items.filter { seen.insert(key($0)).inserted }
        return Paginated(
            items: appended,
            page: incoming.page,
            perPage: incoming.perPage,
            total: incoming.total,
            totalPages: incoming.totalPages,
            hasMore: incoming.hasMore
        )
    }
}
