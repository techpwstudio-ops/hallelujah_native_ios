import Foundation
import Observation

/// One rail's on-screen state. `empty`/`degraded` both arrive from the wire
/// as "no rows right now" but want opposite handling (`HOME_V2_API.md`
/// §3.2/§7): `empty` removes the whole widget (title included); `degraded`
/// keeps the skeleton and gets one automatic retry.
enum HomeRailLoadState: Sendable, Equatable {
    case placeholder
    case loading
    case loaded(ContentSection)
    case degraded
    case empty
    case failed
}

/// Orchestrates `HomeRepository`'s three-endpoint contract into what
/// `HomeView` renders, per `HOME_V2_API.md` §7 ("How the app should use
/// this" / "Rules that matter"). Plays `HomeV2Section`'s state-machine role
/// (`lib/models/home_v2_section.dart`) without its Realm-backed per-row
/// cache — see `HomeFeedCache`'s doc comment for that scope cut.
@Observable
@MainActor
final class HomeFeedViewModel {
    private(set) var placeholders: [HomeSectionPlaceholder] = []
    private(set) var railStates: [String: HomeRailLoadState] = [:]
    private(set) var totalSections = 0
    private(set) var isRefreshing = false
    /// `true` right after a cold start serves the on-disk cache while the
    /// live `refresh()` this same `loadIfNeeded()` call kicks off is still
    /// in flight — lets `HomeView` show a subtle "showing saved content"
    /// affordance instead of a bare skeleton.
    private(set) var loadedFromCache = false

    let contentType: HomeContentType
    private let repository: any HomeRepository
    private let logger = AppLogger(category: .content)

    private static let firstPaintSections = 6
    private static let prefetchWindowSize = 6
    private static let prefetchGap: Duration = .milliseconds(250)
    private static let degradedRetryDelay: Duration = .seconds(1)

    /// Bumped on every fresh layout load (initial load and pull-to-refresh
    /// both funnel through `refresh()`). The prefetch sweep and any
    /// degraded-rail retry capture the generation they started with and
    /// check it before writing — §7: "abandon a prefetch sweep on layout
    /// replacement," generalized here to every piece of background work
    /// this view model starts, not just the sweep itself.
    private var generation = 0

    /// One in-flight request per uiId — §7's de-dupe rule. The prefetch
    /// sweep (keyed `"__sweep__"`), a rail's on-demand fallback
    /// (`ensureLoaded`), and pagination (`loadMore`) can all want the same
    /// uiId at once; a later caller finds the dictionary entry already set
    /// and no-ops instead of issuing a second request.
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// uiIds already given their one automatic degraded-retry this
    /// generation — §3.2 says retry once, not forever.
    private var retriedRails: Set<String> = []

    init(container: DependencyContainer = .current, contentType: HomeContentType = .all) {
        repository = container.resolve()
        self.contentType = contentType
    }

    /// Rank-ordered, with `.empty` rails dropped — §7: "drop empty rails,
    /// widget and title both," so the view never has to branch on this
    /// itself.
    var orderedPlaceholders: [HomeSectionPlaceholder] {
        placeholders
            .filter { railStates[$0.id] != .empty }
            .sorted { $0.rank < $1.rank }
    }

    func state(for uiId: String) -> HomeRailLoadState {
        railStates[uiId] ?? .placeholder
    }

    // MARK: - Initial load / pull-to-refresh

    /// `HomeView`'s `.task` entry point — a no-op past the very first call,
    /// same shape as every other `loadIfNeeded()` in this codebase (view
    /// re-appearances don't re-trigger it; pull-to-refresh calls `refresh()`
    /// directly instead).
    func loadIfNeeded() async {
        guard placeholders.isEmpty else { return }
        if let cached = await repository.cachedLayout(type: contentType) {
            apply(layout: cached, generation: generation)
            loadedFromCache = true
        }
        await refresh()
    }

    /// Pull-to-refresh AND the initial load both funnel through here — the
    /// prefetch sweep it starts always walks every rail from
    /// `firstPaintSections` to `totalSections`, never a hand-maintained
    /// "what's currently on screen" list (§7's explicit warning about a
    /// real prior Dart bug presenting as rails that only ever refresh if
    /// the user happens to be looking at them).
    func refresh() async {
        generation += 1
        let thisGeneration = generation
        retriedRails.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let layout = try await repository.fetchLayout(type: contentType, withSections: Self.firstPaintSections)
            guard thisGeneration == generation else { return }
            loadedFromCache = false
            apply(layout: layout, generation: thisGeneration)
            runPrefetchSweep(startingAt: Self.firstPaintSections, generation: thisGeneration)
        } catch {
            logger.warning("home layout fetch failed: \(error)")
            // Whatever was already on screen (cache-applied above in
            // `loadIfNeeded()`, or a previous refresh's content) stays put;
            // a true cold start with no cache and no network just stays on
            // placeholders.
        }
    }

    /// New placeholders replace the list outright — the layout call is the
    /// one authority on rank order. `railStates` entries the fresh response
    /// doesn't mention are left exactly as they were rather than reset to
    /// `.placeholder`: a rail the sweep hasn't reached yet in THIS
    /// generation keeps showing its last-known content instead of flashing
    /// back to a skeleton mid-refresh.
    private func apply(layout: HomeLayout, generation: Int) {
        placeholders = layout.placeholders
        totalSections = layout.totalSections
        applyOutcomes(sections: layout.hydrated, emptyUiIds: layout.emptyUiIds, degradedUiIds: layout.degradedUiIds, generation: generation)
    }

    private func apply(window: HomeFeedWindow, generation: Int) {
        applyOutcomes(sections: window.sections, emptyUiIds: window.emptyUiIds, degradedUiIds: window.degradedUiIds, generation: generation)
    }

    private func applyOutcomes(sections: [ContentSection], emptyUiIds: Set<String>, degradedUiIds: Set<String>, generation: Int) {
        for section in sections {
            railStates[section.id] = .loaded(section)
        }
        for uiId in emptyUiIds {
            railStates[uiId] = .empty
        }
        for uiId in degradedUiIds {
            railStates[uiId] = .degraded
            scheduleDegradedRetry(uiId: uiId, generation: generation)
        }
    }

    // MARK: - Background prefetch sweep (§7 step 2)

    /// Walks the rest of the layout sequentially, one small window at a
    /// time with a short gap between requests — deliberately not in
    /// parallel, per §7: this is a background sweep competing for the same
    /// bandwidth as whatever the user is actively scrolling toward via
    /// `ensureLoaded`.
    private func runPrefetchSweep(startingAt initialOffset: Int, generation: Int) {
        guard initialOffset < totalSections else { return }
        let task = Task {
            var offset = initialOffset
            while offset < totalSections, generation == self.generation {
                do {
                    let window = try await repository.fetchFeedWindow(
                        type: contentType, offset: offset, limit: Self.prefetchWindowSize
                    )
                    guard generation == self.generation else { return }
                    apply(window: window, generation: generation)
                    guard window.hasMore else { break }
                    offset = window.nextOffset
                } catch {
                    logger.warning("home feed window (offset \(offset)) failed: \(error)")
                    break
                }
                guard generation == self.generation else { return }
                try? await Task.sleep(for: Self.prefetchGap)
            }
            self.inFlight["__sweep__"] = nil
        }
        inFlight["__sweep__"] = task
    }

    // MARK: - On-demand fallback + pagination (§7 steps 3-4)

    /// A rail's placeholder scrolled into view before the prefetch sweep
    /// reached it (or the sweep already gave up after an error) — fetch it
    /// directly. Safe to call on every appearance of the rail's view: it
    /// no-ops unless the rail is genuinely idle (`.placeholder`/`.failed`),
    /// which is also what re-arms a rail that never got a request in the
    /// first place. Meant to be driven by a `.task(id:)` on the row view,
    /// which re-runs on every appearance rather than firing once — §7: a
    /// rail must never permanently sit at "not loaded, not loading, no
    /// error."
    func ensureLoaded(uiId: String) {
        switch state(for: uiId) {
        case .placeholder, .failed:
            break
        case .loading, .loaded, .degraded, .empty:
            return
        }
        guard inFlight[uiId] == nil else { return }
        let thisGeneration = generation
        railStates[uiId] = .loading
        let task = Task {
            await fetchSectionAndApply(uiId: uiId, page: 1, generation: thisGeneration)
        }
        inFlight[uiId] = task
    }

    /// `reloadSection` — the "Tap to retry" affordance on a failed rail: drops
    /// whatever request is in flight for it, forgets that its one automatic
    /// degraded-retry was spent, and asks for it again from scratch.
    func reloadSection(uiId: String) {
        inFlight[uiId]?.cancel()
        inFlight[uiId] = nil
        retriedRails.remove(uiId)
        railStates[uiId] = .placeholder
        ensureLoaded(uiId: uiId)
    }

    /// Reloads a `.degraded` rail once, automatically, shortly after it's
    /// first seen — §3.2's own guidance for the flag. Not repeated: if the
    /// retry also comes back degraded, the rail just stays on its skeleton
    /// until the user's own pull-to-refresh tries again.
    private func scheduleDegradedRetry(uiId: String, generation: Int) {
        guard retriedRails.insert(uiId).inserted else { return }
        guard inFlight[uiId] == nil else { return }
        let task = Task {
            try? await Task.sleep(for: Self.degradedRetryDelay)
            guard generation == self.generation else { return }
            await fetchSectionAndApply(uiId: uiId, page: 1, generation: generation)
        }
        inFlight[uiId] = task
    }

    /// A rail's own "load more" — §7: driven by `meta.hasMore`, never
    /// `items.count`. Appends onto whatever rows the rail already has
    /// rather than replacing them.
    func loadMore(uiId: String) {
        guard case .loaded(let section) = state(for: uiId), section.content.hasMore else { return }
        guard inFlight[uiId] == nil else { return }
        let thisGeneration = generation
        let nextPage = section.content.currentPage + 1
        let task = Task {
            await fetchSectionAndApply(uiId: uiId, page: nextPage, generation: thisGeneration, appendingTo: section)
        }
        inFlight[uiId] = task
    }

    private func fetchSectionAndApply(
        uiId: String, page: Int, generation: Int, appendingTo existing: ContentSection? = nil
    ) async {
        defer { inFlight[uiId] = nil }
        do {
            let outcome = try await repository.fetchSection(type: contentType, uiId: uiId, page: page)
            guard generation == self.generation else { return }
            switch outcome {
            case .loaded(let section):
                railStates[uiId] = .loaded(existing.map { $0.appending(section) } ?? section)
            case .empty:
                // A page 1 fetch with truly nothing hides the rail; a
                // page 2+ "empty" (the rail just ran out of rows in a way
                // `hasMore` didn't already predict) leaves what's on screen.
                if existing == nil {
                    railStates[uiId] = .empty
                }
            case .degraded:
                if existing == nil {
                    if retriedRails.contains(uiId) {
                        // The single automatic retry was spent and the server
                        // is still building this rail — keep its place and
                        // offer "Tap to retry" (`_SectionError`) instead of
                        // shimmering forever.
                        railStates[uiId] = .failed
                    } else {
                        railStates[uiId] = .degraded
                        scheduleDegradedRetry(uiId: uiId, generation: generation)
                    }
                }
                // A degraded page-2+ fetch just leaves page 1's content on
                // screen; the user's own pull-to-refresh can try again later.
            case .malformed:
                if existing == nil {
                    railStates[uiId] = .failed
                }
            }
        } catch {
            guard generation == self.generation else { return }
            logger.warning("home section \(uiId) page \(page) failed: \(error)")
            if existing == nil {
                railStates[uiId] = .failed
            }
        }
    }
}
