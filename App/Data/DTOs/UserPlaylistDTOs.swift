import Foundation

// MARK: - Playlist row/detail

/// `userUserPlaylistIncludes` (`users.user-playlist.includes.js`) selects no
/// scalar columns away, so every response shape below that embeds a
/// playlist row (`createUserPlaylist`/`updateUserPlaylist`/`getUserPlaylist`/
/// `getUserPlaylists`/`getSongsByUserPlaylist`'s `playlist` sibling) sends
/// the same flat row — including the raw `userId` scalar, unnarrowed.
/// Confirmed directly against `prisma/schema.prisma`'s `UserPlaylist` model
/// for the field list.
struct UserPlaylistDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let image: String?
    let imageVariants: String?
    let visibility: String?
    let songsCount: Int?
    let duration: Int?
    let userId: String?
    let createdAt: String?
}

extension UserPlaylistDTO {
    func toDomain() -> UserPlaylist {
        UserPlaylist(
            id: id,
            title: sanitized(title) ?? "",
            description: sanitized(description),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            visibility: sanitized(visibility),
            songsCount: songsCount,
            duration: duration,
            ownerUserID: sanitized(userId),
            createdAt: Date.parseFlexibleISO8601(createdAt)
        )
    }
}

// MARK: - Requests

/// `createUserPlaylist`'s body — `{title, songId?}`. `songId` is only read
/// by the controller for the create call (the seeding flow, e.g. an
/// add-to-playlist sheet's "New playlist" button); `RemoteUserPlaylistRepository`
/// sends `nil` for every T45 call site since that sheet is out of scope.
struct CreateUserPlaylistRequest: Encodable, Sendable {
    let title: String
    let songId: String?
}

/// `updateUserPlaylist`'s body — the controller reads only `title`.
struct RenameUserPlaylistRequest: Encodable, Sendable {
    let title: String
}

/// `attachSongsToPlaylist`/`detachSongsFromPlaylist`'s shared body shape.
struct UserPlaylistSongIdsRequest: Encodable, Sendable {
    let songIds: [String]
}

// MARK: - Single-playlist envelope

/// `createUserPlaylist`/`updateUserPlaylist`/`togglePlaylistVisibility`'s
/// shared `{message, data: <playlist>}` shape, and `getUserPlaylist`'s
/// identical `{data: <playlist>}` (no `message` sent, but the field is
/// unused here anyway so its absence doesn't matter).
struct UserPlaylistResponseDTO: Decodable, Sendable {
    let data: UserPlaylistDTO
}

/// `{message}` — the toast text Dart shows for follow/visibility responses.
struct UserPlaylistMessageDTO: Decodable, Sendable {
    let message: String?
}

// MARK: - List envelope

/// `getUserPlaylists`/`getSongsByUserPlaylist`'s shared meta shape
/// (`userPlaylist.controller.js`) — confirmed directly, both literally
/// return `{total, page, perPage, totalPages}`. Not `LegacyPaginationMetaDTO`
/// (`CreatorProfileDTOs.swift`): that decodes a `count` key, this wire sends
/// `total` instead — a genuinely different shape, not a duplicate.
struct UserPlaylistsPaginationMetaDTO: Decodable, Sendable {
    let total: Int?
    let page: Int?
    let perPage: Int?
    let totalPages: Int?
}

/// `getUserPlaylists`' response. The wire's per-row `isOwner`/`isFollowing`/
/// `isFollowed` computed flags are deliberately left undecoded here — see
/// `UserPlaylist`'s own doc comment for why ownership is derived client-side
/// instead of trusting them.
struct UserPlaylistsResponseDTO: Decodable, Sendable {
    let data: [UserPlaylistDTO]?
    let meta: UserPlaylistsPaginationMetaDTO?
}

extension UserPlaylistsResponseDTO {
    func toDomain() -> Paginated<UserPlaylist> {
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

// MARK: - Songs envelope

/// `getSongsByUserPlaylist`'s response: the playlist header travels as a
/// sibling `playlist` key, not nested under `data` — `data` here is the
/// songs array, a different envelope shape from every other endpoint above.
/// Confirmed directly against the controller; the endpoint's own `@openapi`
/// doc comment above it is stale and describes a flat `{count, songs: [...]}`
/// shape that doesn't match the real response.
struct UserPlaylistSongsResponseDTO: Decodable, Sendable {
    let playlist: UserPlaylistDTO?
    let meta: UserPlaylistsPaginationMetaDTO?
    let data: [SongDTO]?
}

extension UserPlaylistSongsResponseDTO {
    /// `nil` only if `playlist` is missing from a 200 response, which
    /// shouldn't happen — the endpoint 404s first when the playlist itself
    /// doesn't exist — but there's no reasonable domain default for a
    /// missing owner to invent here.
    func toDomain() -> UserPlaylistSongsPage? {
        guard let playlist else { return nil }
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        let songs = Paginated<Song>(
            items: (data ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
        return UserPlaylistSongsPage(playlist: playlist.toDomain(), songs: songs)
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
