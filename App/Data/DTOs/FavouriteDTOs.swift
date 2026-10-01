import Foundation

/// `getFavoriteSongs`/`getFavoriteCreators` (`songs.controller.js`/
/// `creators.controller.js`) both wrap their rows in `{data, meta: {total,
/// page, perPage, totalPages}}` — the same field names as `PaginationMetaDTO`
/// (`ContentDTOs.swift`), reused here rather than `LegacyPaginationMetaDTO`
/// (which has `count`, not `total`). Neither endpoint actually sends a
/// `hasMore` field on the wire despite `PaginationMetaDTO` declaring one
/// (confirmed directly against both controllers) — `PaginatedDTO<Item>`'s
/// own generic `toDomain(_:)` trusts `meta?.hasMore` outright, so it isn't
/// reused verbatim; both DTOs below derive `hasMore` themselves
/// (`page < totalPages`), the same derivation every other legacy-meta
/// response in this app already uses.
struct FavoriteSongsResponseDTO: Decodable, Sendable {
    let data: [SongDTO]?
    let meta: PaginationMetaDTO?
}

extension FavoriteSongsResponseDTO {
    func toDomain() -> Paginated<Song> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

struct FavoriteCreatorsResponseDTO: Decodable, Sendable {
    let data: [CreatorDTO]?
    let meta: PaginationMetaDTO?
}

extension FavoriteCreatorsResponseDTO {
    func toDomain() -> Paginated<Creator> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}
