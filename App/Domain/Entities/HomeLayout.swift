import Foundation

/// One rail's identity before it has content, straight from `/v2/home/
/// layout/:type` (`HOME_V2_API.md` §3.1). Mirrors `HomeV2Section`'s own
/// two-phase split (`lib/models/home_v2_section.dart`) — a placeholder is
/// drawn immediately in `rank` order (a skeleton), then replaced — not
/// mutated — by a real `ContentSection` once that rail hydrates.
struct HomeSectionPlaceholder: Sendable, Equatable, Identifiable {
    let id: String
    let key: String
    let title: String
    let viewType: String
    let type: String
    let rank: Int
    /// The server's hint that this rail is worth prioritizing for first
    /// paint. Advisory only — every rail still eventually loads.
    let eager: Bool
    let paginated: Bool
    /// Whether this rail's contents depend on the signed-in user. Never
    /// cache a `personalized` rail's rows across accounts on the device.
    let personalized: Bool
}

/// What one section response resolved to, per `HOME_V2_API.md` §3.2's two
/// independent flags — `empty` and `degraded` both arrive as `data: []` but
/// want opposite handling (hide vs. keep-skeleton-and-retry), so they can't
/// collapse into a single `ContentSection?`.
enum HomeSectionOutcome: Sendable {
    case loaded(ContentSection)
    /// No rows for this user, on page 1 — remove the widget, title included.
    case empty(uiId: String)
    /// The server hit its deadline; NOT the same as empty — keep the
    /// skeleton and retry once, per §3.2/§7.
    case degraded(uiId: String)
    /// The response was missing what's needed to even place the rail
    /// (`uiId`/`id`, `viewType`) — a genuinely malformed response.
    case malformed
}

/// One `GET /v2/home/layout/:type?withSections=N` response, decoded.
/// `hydrated`/`emptyUiIds`/`degradedUiIds` are only meaningful when the
/// request used `withSections > 0` — the only way this app calls it
/// (`HomeFeedViewModel` always asks for the first-paint window in the same
/// round trip).
struct HomeLayout: Sendable {
    let placeholders: [HomeSectionPlaceholder]
    let hydrated: [ContentSection]
    /// Rails among `hydrated` that came back with no rows — remove the
    /// widget and its title. Also seeded from the layout's own top-level
    /// `emptyUiIds` (§3.1's own field, same contract as `/feed`'s).
    let emptyUiIds: Set<String>
    /// Rails among `hydrated` whose OWN hydration hit its deadline — keep
    /// their skeleton and retry once, same as any other degraded rail.
    let degradedUiIds: Set<String>
    let totalSections: Int
    /// `true` when the layout QUERY itself missed its deadline — the
    /// dynamic rails (per-language, per-category, "This Week's Top
    /// Playlist") are missing wholesale from `placeholders`. Render what
    /// arrived, but per §3.1's own guidance, don't cache it for the
    /// session — ask again on the next open.
    let degraded: Bool
}

/// One `GET /v2/home/feed/:type?offset=&limit=` response, decoded — a
/// window of already-hydrated rails, applied over their matching
/// placeholders in the order the layout already established.
struct HomeFeedWindow: Sendable {
    let sections: [ContentSection]
    /// Rails in this window that came back with no rows — remove the
    /// widget and its title, per §3.3/§7's explicit guidance. Does NOT
    /// include a `degraded` rail; that one keeps its skeleton.
    let emptyUiIds: Set<String>
    /// Rails in this window whose OWN hydration hit its deadline.
    let degradedUiIds: Set<String>
    let hasMore: Bool
    let nextOffset: Int
    /// `true` when this window was sliced out of a short (degraded)
    /// layout — `hasMore`/`nextOffset`/`emptyUiIds` describe a layout that
    /// isn't the real one. Render the window; don't persist those three.
    let degraded: Bool
}
