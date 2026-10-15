import Foundation

// MARK: - Layout (`GET /v2/home/layout/:type`, `HOME_V2_API.md` §3.1)

struct HomeLayoutSectionDTO: Decodable, Sendable {
    let id: String?
    let uiId: String?
    let key: String?
    let title: String?
    let viewType: String?
    let rank: Int?
    let type: String?
    let eager: Bool?
    let paginated: Bool?
    let personalized: Bool?
}

extension HomeLayoutSectionDTO {
    func toDomain() -> HomeSectionPlaceholder? {
        guard let identity = sanitized(uiId) ?? sanitized(id), let resolvedViewType = sanitized(viewType) else {
            return nil
        }
        return HomeSectionPlaceholder(
            id: identity,
            key: sanitized(key) ?? resolvedViewType,
            title: sanitized(title) ?? "",
            viewType: resolvedViewType,
            type: sanitized(type) ?? "all",
            rank: rank ?? 0,
            eager: eager ?? false,
            paginated: paginated ?? false,
            personalized: personalized ?? false
        )
    }
}

struct HomeLayoutDataDTO: Decodable, Sendable {
    let type: String?
    let version: Int?
    let count: Int?
    let totalSections: Int?
    let hydratedCount: Int?
    let emptyUiIds: [String]?
    let hydrated: [HomeSectionResponseDTO]?
    let sections: [HomeLayoutSectionDTO]?
    let degraded: Bool?
}

struct HomeLayoutResponseDTO: Decodable, Sendable {
    let data: HomeLayoutDataDTO
}

extension HomeLayoutResponseDTO {
    func toDomain() -> HomeLayout {
        var hydrated: [ContentSection] = []
        var emptyUiIds = Set(data.emptyUiIds ?? [])
        var degradedUiIds: Set<String> = []
        for outcome in (data.hydrated ?? []).map({ $0.toOutcome() }) {
            switch outcome {
            case .loaded(let section):
                hydrated.append(section)
            case .empty(let uiId):
                emptyUiIds.insert(uiId)
            case .degraded(let uiId):
                degradedUiIds.insert(uiId)
            case .malformed:
                break
            }
        }
        return HomeLayout(
            placeholders: (data.sections ?? []).compactMap { $0.toDomain() },
            hydrated: hydrated,
            emptyUiIds: emptyUiIds,
            degradedUiIds: degradedUiIds,
            totalSections: data.totalSections ?? data.count ?? 0,
            degraded: data.degraded ?? false
        )
    }
}

// MARK: - Section response (`GET /v2/home/section/:type/:uiId`, §3.2 — also
// the shape of each element in `/feed`'s `data[]`, §3.3)

struct HomeSectionMetaDTO: Decodable, Sendable {
    let page: Int?
    let perPage: Int?
    let total: Int?
    let totalPages: Int?
    let hasMore: Bool?
}

/// One hydrated rail. `rows` decodes generically (`JSONValue`) since its
/// concrete row shape depends on `viewType` — see `HomeSectionContentDecoder`.
struct HomeSectionResponseDTO: Decodable, Sendable {
    let id: String?
    let uiId: String?
    let key: String?
    let viewType: String?
    let rank: Int?
    let type: String?
    let title: String?
    let meta: HomeSectionMetaDTO?
    let cache: String?
    let empty: Bool?
    let degraded: Bool?
    let rows: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, uiId, key, viewType, rank, type, title, meta, cache, empty, degraded
        case rows = "data"
    }
}

extension HomeSectionResponseDTO {
    /// `empty`/`degraded` both arrive as `data: []` (§3.2) but want opposite
    /// handling, so they're kept as distinct `HomeSectionOutcome` cases
    /// rather than collapsed into "a `ContentSection` with zero rows" —
    /// see `HomeSectionOutcome`'s doc comment.
    func toOutcome() -> HomeSectionOutcome {
        guard let identity = sanitized(uiId) ?? sanitized(id), let resolvedViewType = sanitized(viewType) else {
            return .malformed
        }
        if degraded == true {
            return .degraded(uiId: identity)
        }
        if empty == true {
            return .empty(uiId: identity)
        }
        return .loaded(ContentSection(
            id: identity,
            key: sanitized(key) ?? resolvedViewType,
            title: sanitized(title) ?? "",
            viewType: resolvedViewType,
            type: sanitized(type) ?? "all",
            rank: rank ?? 0,
            content: HomeSectionContentDecoder.decode(viewType: resolvedViewType, rows: rows ?? [], meta: meta)
        ))
    }
}

/// Dispatches one rail's raw `data[]` rows to the right domain type by
/// `viewType`, per `HOME_V2_API.md` §4's section catalogue:
/// `trending`/`songs`/`listSongs` → Song; `creators` → Creator;
/// `companyPlaylists`/`aiPlaylist`/`singleCompanyPlaylist`/`similarPlaylist`
/// → CompanyPlaylist-shaped (§6.4 confirms `similarPlaylist` rows are
/// "ordinary CompanyPlaylist objects, identical in shape to the seed", plus
/// `isSeed`); `playlists` → CreatorPlaylist-shaped; `recentMixed` →
/// already-resolved mixed cards.
///
/// `podcasts` (§4: "Creator + `songs[]`, latest 3 episodes" — no JSON
/// example in the spec to ground a bespoke shape against) and `verseOfDay`
/// (Bible content — M9's concern, not this feature's) both fall through to
/// `.unsupported` deliberately, same as any future `viewType` this build
/// doesn't recognize yet — mirrors Dart's own graceful-degradation
/// convention for exactly this (`car_play_service.dart`'s "skipping
/// unrecognized viewType" log).
enum HomeSectionContentDecoder {
    static func decode(viewType: String, rows: [JSONValue], meta: HomeSectionMetaDTO?) -> SectionContent {
        func paginate<T: Sendable>(_ items: [T]) -> Paginated<T> {
            Paginated(
                items: items,
                page: meta?.page ?? 1,
                perPage: meta?.perPage,
                total: meta?.total,
                totalPages: meta?.totalPages ?? 1,
                hasMore: meta?.hasMore ?? false
            )
        }

        switch viewType {
        // `recommended` and `episodes` are plain song rails (`car_play_service.dart`'s
        // `_flatSongViewTypes`; `home_section_builder.dart`'s builders).
        case "trending", "songs", "listSongs", "recommended", "episodes":
            return .songs(paginate(decodeRows(rows, as: SongDTO.self).map { $0.toDomain() }))
        // `podcasts` renders a creator row with a see-all-artists target.
        case "creators", "podcasts":
            return .creators(paginate(decodeRows(rows, as: CreatorDTO.self).map { $0.toDomain() }))
        case "companyPlaylists", "aiPlaylist", "singleCompanyPlaylist", "similarPlaylist":
            return .playlists(paginate(decodeRows(rows, as: CompanyPlaylistDTO.self).map { $0.toDomain() }))
        case "playlists":
            return .playlists(paginate(decodeRows(rows, as: CreatorPlaylistDTO.self).map { $0.toDomain() }))
        case "recentMixed":
            return .recentItems(paginate(decodeRows(rows, as: RecentContentItemDTO.self).map { $0.toDomain() }))
        case "verseOfDay":
            // Not a rail: `syncHomePageUiItems*` stores the first row and makes
            // it the current verse (`last_verse_of_day_id`); `VerseOfDayCardView`
            // renders it from that cache.
            VerseOfDayIngest.ingestHomeRows(rows)
            return .unsupported(viewType: viewType)
        default:
            return .unsupported(viewType: viewType)
        }
    }

    private static func decodeRows<T: Decodable>(_ rows: [JSONValue], as type: T.Type) -> [T] {
        guard let data = try? JSONEncoder().encode(rows) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }
}

// MARK: - Feed window (`GET /v2/home/feed/:type`, §3.3)

struct HomeFeedMetaDTO: Decodable, Sendable {
    let offset: Int?
    let limit: Int?
    let returned: Int?
    let totalSections: Int?
    let hasMore: Bool?
    let nextOffset: Int?
    let degraded: Bool?
    let emptyUiIds: [String]?
}

struct HomeFeedResponseDTO: Decodable, Sendable {
    let data: [HomeSectionResponseDTO]
    let meta: HomeFeedMetaDTO?
}

extension HomeFeedResponseDTO {
    func toDomain() -> HomeFeedWindow {
        var sections: [ContentSection] = []
        var emptyUiIds = Set(meta?.emptyUiIds ?? [])
        var degradedUiIds: Set<String> = []
        for outcome in data.map({ $0.toOutcome() }) {
            switch outcome {
            case .loaded(let section):
                sections.append(section)
            case .empty(let uiId):
                emptyUiIds.insert(uiId)
            case .degraded(let uiId):
                degradedUiIds.insert(uiId)
            case .malformed:
                break
            }
        }
        return HomeFeedWindow(
            sections: sections,
            emptyUiIds: emptyUiIds,
            degradedUiIds: degradedUiIds,
            hasMore: meta?.hasMore ?? false,
            nextOffset: meta?.nextOffset ?? 0,
            degraded: meta?.degraded ?? false
        )
    }
}
