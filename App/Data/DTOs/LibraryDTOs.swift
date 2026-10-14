import Foundation

// MARK: - Counts

/// `getLibraryCount`'s response (`library.controller.js`) — `playlists`/
/// `savedItems` are present on the wire but unused even by Dart's own bloc
/// (see `Library.swift`'s `LibraryCounts` doc comment), so left off here.
struct LibraryCountsResponseDTO: Decodable, Sendable {
    struct DataDTO: Decodable, Sendable {
        let favoriteMusic: Int?
        let favoriteEpisodes: Int?
        let favoriteCreators: Int?
    }

    let data: DataDTO?
}

extension LibraryCountsResponseDTO {
    func toDomain() -> LibraryCounts {
        LibraryCounts(
            likedMusic: data?.favoriteMusic ?? 0,
            likedEpisodes: data?.favoriteEpisodes ?? 0,
            likedArtists: data?.favoriteCreators ?? 0
        )
    }
}

// MARK: - Items

/// `GET /library/items`'s per-row shape (`getLibraryItems`, merging
/// `toUserPlaylistRow`'s output with `hydrateLibraryItems`'s
/// `creatorPlaylist`/`companyPlaylist` rows) — every row carries a
/// discriminating `itemType`, decoded first via a probe since Swift has no
/// native discriminated-union decoding.
private struct LibraryItemTypeProbeDTO: Decodable {
    let itemType: String?
}

/// `toUserPlaylistRow`'s shape (`library.controller.js`) — bare fields; no
/// `UserPlaylist` domain model exists yet (T45), so this stays a DTO-local
/// tuple rather than mapping to a domain entity, mirroring
/// `AppRoute.userPlaylistSongs` staying id-only for the same reason.
struct LibraryUserPlaylistRowDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let image: String?
    let imageVariants: String?
    let songsCount: Int?
    let isOwner: Bool?
}

/// `creatorPlaylist`/`companyPlaylist` rows (`STRATEGIES.creatorPlaylist
/// .toRow`/`STRATEGIES.companyPlaylist.toRow`, `library.helpers.js`) — both
/// map onto the same `Playlist` domain entity `CompanyPlaylistDTO`/
/// `CreatorPlaylistDTO` already do (`ContentDTOs.swift`), but this
/// endpoint's `creatorPlaylist` rows send a FLAT `creatorName` field rather
/// than `CreatorPlaylistDTO`'s nested `creator: {name}` — confirmed
/// directly against `toRow`'s literal object shape — so those two existing
/// DTOs can't be reused verbatim here.
struct LibraryPlaylistRowDTO: Decodable, Sendable {
    let itemType: String?
    let id: String
    let title: String?
    let description: String?
    let image: String?
    let imageVariants: String?
    let type: String?
    let language: String?
    let visibility: String?
    let rank: Int?
    let duration: Int?
    let songsCount: Int?
    let activeSongsCount: Int?
    let creatorId: String?
    let creatorName: String?
    let createdAt: String?
}

extension LibraryPlaylistRowDTO {
    func toDomain() -> Playlist {
        let isCompany = itemType == "companyPlaylist"
        return Playlist(
            id: id,
            title: sanitized(title) ?? "",
            description: sanitized(description),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            type: sanitized(type),
            visibility: sanitized(visibility),
            language: sanitized(language),
            songsCount: songsCount ?? activeSongsCount,
            // `duration`/`rank` mirror `CompanyPlaylistDTO`/`CreatorPlaylistDTO`'s
            // own split (`ContentDTOs.swift`): each field is only ever
            // meaningful for one owner kind, regardless of what the wire
            // literally sends for the other (e.g. `companyPlaylist` rows send
            // a literal `duration: 0`, not omitted — nilled here anyway to
            // match `Playlist.duration`'s own "CreatorPlaylist only" contract).
            duration: isCompany ? nil : duration,
            rank: isCompany ? rank : nil,
            owner: isCompany ? .company : .creator(id: creatorId, name: sanitized(creatorName)),
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: nil,
            isSeed: false
        )
    }
}

enum LibraryItemRowDTO: Sendable {
    case playlist(LibraryPlaylistRowDTO)
    case userPlaylist(LibraryUserPlaylistRowDTO)
    /// A row whose `itemType` isn't one of the three known values — decoded
    /// rather than thrown, so one unexpected row doesn't fail the whole
    /// page (mirrors `hydrateLibraryItems`'s own skip-if-unrecognized
    /// posture, `library.helpers.js`).
    case unknown
}

extension LibraryItemRowDTO: Decodable {
    init(from decoder: Decoder) throws {
        let probe = try LibraryItemTypeProbeDTO(from: decoder)
        switch probe.itemType {
        case "userPlaylist":
            self = try .userPlaylist(LibraryUserPlaylistRowDTO(from: decoder))
        case "creatorPlaylist", "companyPlaylist":
            self = try .playlist(LibraryPlaylistRowDTO(from: decoder))
        default:
            self = .unknown
        }
    }
}

extension LibraryItemRowDTO {
    func toDomain() -> LibraryEntry? {
        switch self {
        case let .playlist(dto):
            return .playlist(dto.toDomain())
        case let .userPlaylist(dto):
            return .userPlaylist(
                id: dto.id,
                title: sanitized(dto.title) ?? "",
                image: sanitized(dto.image),
                imageVariants: sanitized(dto.imageVariants),
                songsCount: dto.songsCount,
                isOwner: dto.isOwner ?? false
            )
        case .unknown:
            return nil
        }
    }
}

/// `getLibraryItems`'s envelope — same `{data: [...], meta: {...}}` /
/// `LegacyPaginationMetaDTO` shape `PlaylistSongsResponseDTO` already uses.
struct LibraryItemsResponseDTO: Decodable, Sendable {
    let data: [LibraryItemRowDTO]?
    let meta: LegacyPaginationMetaDTO?
}

extension LibraryItemsResponseDTO {
    func toDomain() -> Paginated<LibraryEntry> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data ?? []).compactMap { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.count,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

// MARK: - Shared helper

private func sanitized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "undefined" { return nil }
    return trimmed
}

/// `GET /library/items/ids` — `{ data: ["creatorPlaylist:<id>", …] }`.
struct LibraryItemIDsResponseDTO: Decodable, Sendable {
    let data: [String]
}

/// `POST /library/items/:type/:id/toggle` — `{ data: { inLibrary } }`.
struct LibraryToggleResponseDTO: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let inLibrary: Bool?
    }

    let data: Payload?
}
