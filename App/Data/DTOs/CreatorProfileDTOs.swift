import Foundation

/// New file rather than an addition to `ContentDTOs.swift`: T30's own DTOs
/// only ever wrap `CreatorDTO`/`SongDTO`/`CreatorPlaylistDTO` (built in T27),
/// so nothing here duplicates `sanitized(_:)` or any other shared mapper
/// logic already defined there.

// MARK: - Single-creator envelopes

/// `{ message, data: <creator> }` — `getCreatorApi` (`GET /creator/:id`).
struct CreatorDetailResponseDTO: Decodable, Sendable {
    let data: CreatorDTO
}

/// `{ data: [<creator>, ...] }` — `followCreatorApi`/`unfollowCreatorApi`'s
/// shared response shape (`attachCreators`/`detachCreator`,
/// `lib/blocs/favourite/bloc.dart`). No `meta`: these aren't paginated lists,
/// just "the rows for the ids you just sent."
struct CreatorListResponseDTO: Decodable, Sendable {
    let data: [CreatorDTO]
}

// MARK: - Legacy (pre-V2) pagination

/// `PaginationModel.fromJson` (`lib/models/CategoryPageData.dart`) — the
/// OLDER `{page, perPage, totalPages, count}` meta shape `getCreatorSongsApi`/
/// `getCreatorPlaylistsApi` still use. No `hasMore` field on this wire shape;
/// callers derive it the same way Dart's own `PaginationModel.hasNextPage`
/// does (`page < totalPages`).
struct LegacyPaginationMetaDTO: Decodable, Sendable {
    let page: Int?
    let perPage: Int?
    let totalPages: Int?
    let count: Int?
}

struct CreatorSongsResponseDTO: Decodable, Sendable {
    let data: [SongDTO]
    let meta: LegacyPaginationMetaDTO?
}

extension CreatorSongsResponseDTO {
    func toDomain() -> Paginated<Song> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: data.map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.count,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

/// Despite `creator_playlist_provider.dart` calling `getSongFromJson` on
/// these rows (a Dart-side copy/paste bug against its OWN `getCreatorPlaylistFromJson`
/// parser, since `PlaylistListItem` — what actually renders this list —
/// reads playlist fields), the endpoint is `getCreatorPlaylistsApi`, so the
/// wire shape decoded here is `CreatorPlaylistDTO`, matching what the row it
/// renders through (`PlaylistListItem`) actually expects — the real contract,
/// not Dart's buggy parse.
struct CreatorPlaylistsResponseDTO: Decodable, Sendable {
    let data: [CreatorPlaylistDTO]
    let meta: LegacyPaginationMetaDTO?
}

extension CreatorPlaylistsResponseDTO {
    func toDomain() -> Paginated<Playlist> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: data.map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.count,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

// MARK: - Follow/unfollow requests

/// `attachCreators` (`lib/blocs/favourite/bloc.dart`): `{detach, ids}`.
/// `detach` is always `false` from this screen's own follow action — the
/// bloc's own `sync` parameter (a bulk detach-then-attach reconciliation
/// path) has no call site that passes `true`.
struct FollowCreatorsRequest: Encodable, Sendable {
    let detach: Bool
    let ids: [String]
}

/// `detachCreator`: `{ids}`.
struct UnfollowCreatorsRequest: Encodable, Sendable {
    let ids: [String]
}
