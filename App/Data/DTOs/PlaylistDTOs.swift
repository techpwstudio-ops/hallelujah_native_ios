import Foundation

/// `getPlaylistSongs`/`getCompanyPlaylistSongs`'s shared response shape
/// (`lib/blocs/album/bloc.dart`, `lib/blocs/company_playlist_songs/bloc.dart`):
/// `{ data: { songs: [...] }, meta: {...} }` — `data` is an OBJECT with a
/// `songs` key, unlike `CreatorSongsResponseDTO`'s bare-array `data`
/// (`CreatorProfileDTOs.swift`). Same older `{page, perPage, totalPages,
/// count}` meta shape as that file, reused rather than duplicated
/// (`LegacyPaginationMetaDTO`).
struct PlaylistSongsResponseDTO: Decodable, Sendable {
    struct DataDTO: Decodable, Sendable {
        let songs: [SongDTO]?
    }

    let data: DataDTO?
    let meta: LegacyPaginationMetaDTO?
}

extension PlaylistSongsResponseDTO {
    func toDomain() -> Paginated<Song> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data?.songs ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.count,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}
