import Foundation

// MARK: - Search (T40/T41) — `GET /api/search` (`SEARCH_API.md`).

/// `Creator Object` (`SEARCH_API.md`) as `creators.data` sends it — decodes
/// directly into `SearchCreatorResult`'s shape rather than through an
/// intermediate DTO+domain pair like `CreatorDTO`/`Creator`: search's own
/// creator rows are already the minimal shape that domain type models
/// (`artist_search_item.dart` confirms `displayName`/`followers` are real
/// wire fields nothing in this app's search UI reads), so a second mapping
/// step would have nothing to add.
struct SearchCreatorDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let image: String?
    let imageVariants: String?
    let followersCount: Int?
}

extension SearchCreatorDTO {
    func toDomain() -> SearchCreatorResult {
        SearchCreatorResult(
            id: id,
            name: sanitized(name),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            followersCount: followersCount
        )
    }
}

/// `Playlist Object`'s flat `owner` (`playlistSearchResult.js`'s
/// `toUserPlaylistResult`/`toCompanyPlaylistResult`, both `{id, name,
/// image}`) — only `.name` is ever rendered (`SearchPlaylistResult.ownerName`'s
/// own doc comment), so `.id`/`.image` aren't decoded.
struct SearchPlaylistOwnerRefDTO: Decodable, Sendable {
    let name: String?
}

/// `Playlist Object` (`SEARCH_API.md`) as `playlists.data` sends it —
/// decodes directly into `SearchPlaylistResult`'s shape, same reasoning as
/// `SearchCreatorDTO`.
struct SearchPlaylistDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let image: String?
    let imageVariants: String?
    let ownerType: SearchPlaylistOwnerType?
    let owner: SearchPlaylistOwnerRefDTO?
    let visibility: String?
}

extension SearchPlaylistDTO {
    func toDomain() -> SearchPlaylistResult {
        SearchPlaylistResult(
            id: id,
            title: sanitized(title),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            // Absent `ownerType` is a user playlist, never a dropped row —
            // `PlaylistSearchItem.keyFor`'s own doc comment: "anything that
            // isn't `company` — including the field being absent, which is
            // what an older server sends — is a user playlist, i.e. today's
            // behaviour."
            ownerType: ownerType ?? .user,
            ownerName: sanitized(owner?.name),
            visibility: sanitized(visibility)
        )
    }
}

/// `topResult` (`SEARCH_API.md`): `{type, item}`, where `item`'s concrete
/// shape depends on `type`. Decoded the same two-step way
/// `HomeSectionContentDecoder` (`HomeDTOs.swift`) decodes a rail's rows:
/// `item` first as a generic `JSONValue`, then re-encoded and decoded a
/// second time as the concrete DTO `type` names, once `type` itself is
/// known — keeps this decode plain compiler-synthesized `Codable` same as
/// every other DTO here, no hand-written `Decoder` traversal.
struct TopResultDTO: Decodable, Sendable {
    let type: String?
    let item: JSONValue?
}

extension TopResultDTO {
    /// `nil` if `type`/`item` are missing, `type` isn't one of the four
    /// documented wire strings, or `item` fails to decode as that type's
    /// shape — none of which are crash-worthy: the rest of the response
    /// (the four sections) still renders without a top result.
    ///
    /// Matches `type` against its own literal wire strings — `"music"` |
    /// `"episode"` | `"creator"` | `"playlist"`, all `SEARCH_API.md`'s
    /// `topResult` section — deliberately NOT `SearchFilter(rawValue:)`:
    /// that enum's playlist case is `.playlists`, raw value `"playlists"`
    /// (PLURAL), a different string that would silently fail to match a
    /// `"playlist"` (singular) top result every time.
    func toDomain() -> SearchTopResultItem? {
        guard let type, let item, let data = try? JSONEncoder().encode(item) else { return nil }
        switch type {
        case "music", "episode":
            return (try? JSONDecoder().decode(SongDTO.self, from: data)).map { .song($0.toDomain()) }
        case "creator":
            return (try? JSONDecoder().decode(SearchCreatorDTO.self, from: data)).map { .creator($0.toDomain()) }
        case "playlist":
            return (try? JSONDecoder().decode(SearchPlaylistDTO.self, from: data)).map { .playlist($0.toDomain()) }
        default:
            return nil
        }
    }
}

/// `GET /api/search`'s full response (`SEARCH_API.md`). Every section key
/// may be entirely absent (a filtered response's inactive sections) or
/// present as `{data: [], meta: {}}` — optionality on every property here,
/// plus `toDomain()`'s `?? []` fallback, handles both the same way without a
/// bespoke "maybe absent" wrapper. The legacy `songs` key
/// (`SEARCH_API.md`: "present for backward compatibility... new app must
/// ignore it") has no property here at all — omission is enough, since
/// `Decodable` never requires every wire key to be modeled.
struct SearchResponseDTO: Decodable, Sendable {
    let topResult: TopResultDTO?
    let music: PaginatedDTO<SongDTO>?
    let episodes: PaginatedDTO<SongDTO>?
    let creators: PaginatedDTO<SearchCreatorDTO>?
    let playlists: PaginatedDTO<SearchPlaylistDTO>?
}

extension SearchResponseDTO {
    func toDomain() -> SearchResults {
        SearchResults(
            topResult: topResult?.toDomain(),
            music: paginate(music) { $0.toDomain() },
            episodes: paginate(episodes) { $0.toDomain() },
            creators: paginate(creators) { $0.toDomain() },
            playlists: paginate(playlists) { $0.toDomain() }
        )
    }

    /// `meta`'s wire shape here (`SEARCH_API.md`: `{total, page, perPage,
    /// totalPages}`) has no `hasMore`, unlike Home's own section `meta`
    /// (`HomeSectionMetaDTO`) — so `PaginatedDTO.toDomain(_:)`'s default
    /// `hasMore: meta?.hasMore ?? false` would silently produce `false`
    /// forever here, breaking pagination after page 1. This computes it the
    /// same "page < totalPages" way `Paginated` already documents as the
    /// fallback its own callers are trusted to use when a server doesn't
    /// send the field directly.
    private func paginate<Item: Sendable, Domain: Sendable>(
        _ dto: PaginatedDTO<Item>?,
        _ transform: (Item) -> Domain?
    ) -> Paginated<Domain> {
        let page = dto?.meta?.page ?? 1
        let totalPages = dto?.meta?.totalPages ?? 1
        return Paginated(
            items: (dto?.data ?? []).compactMap(transform),
            page: page,
            perPage: dto?.meta?.perPage,
            total: dto?.meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

/// Local duplicate of `ContentDTOs.swift`'s equivalent helper (`private`
/// there, so not reachable from this file) — same behavior: treats the
/// literal strings `"null"`/`"undefined"` as absent, same as every other
/// DTO's mapper in this app.
private func sanitized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "undefined" { return nil }
    return trimmed
}
