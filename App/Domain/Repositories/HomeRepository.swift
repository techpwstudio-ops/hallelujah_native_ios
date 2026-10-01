/// The V2 lazy-loading home feed's three-endpoint contract
/// (`HOME_V2_API.md` §3) — ports the app's own `getHomeV2LayoutApi`/
/// `getHomeV2FeedApi`/`getHomeV2SectionApi` (`end_points.dart:110-130`) call
/// sites, not `HomeV2Section`'s Realm-backed state machine, which is this
/// feature's `HomeFeedViewModel`'s job instead.
protocol HomeRepository: Sendable {
    /// §3.1 — the manifest, called once per home-screen open.
    /// `withSections` front-loads that many rails' content into the same
    /// response; this app always passes a positive count (see
    /// `HomeFeedViewModel`), never the bare-manifest `0` case.
    func fetchLayout(type: HomeContentType, withSections: Int) async throws -> HomeLayout

    /// §3.3 — a window of rails hydrated together, in layout order. The
    /// background prefetch-sweep path.
    func fetchFeedWindow(type: HomeContentType, offset: Int, limit: Int) async throws -> HomeFeedWindow

    /// §3.2 — one rail, on demand: the fallback when a placeholder reaches
    /// the viewport before the prefetch sweep gets to it, and the only path
    /// for `page=2+`. Returns `.empty`/`.degraded` rather than throwing for
    /// those two cases — see `HomeSectionOutcome`.
    func fetchSection(type: HomeContentType, uiId: String, page: Int) async throws -> HomeSectionOutcome

    /// The last successfully-cached `/layout` response for `type`, if any —
    /// `HomeFeedViewModel`'s cold-start / offline path. `nil` when nothing
    /// has ever been cached, same as a cache miss.
    func cachedLayout(type: HomeContentType) async -> HomeLayout?
}
