import Foundation

// MARK: - Pagination

/// The `meta` object every paginated content endpoint sends
/// (`HomeV2Section.hydrated`'s `json['meta']`: `page`/`totalPages`/
/// `hasMore` — see `Paginated.swift` for why this shape is trusted as the
/// common one).
struct PaginationMetaDTO: Decodable, Sendable {
    let page: Int?
    let perPage: Int?
    let total: Int?
    let totalPages: Int?
    let hasMore: Bool?
}

/// `{ data: [Item], meta: {...} }` — the envelope every paginated content
/// endpoint wraps its rows in.
struct PaginatedDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: [Item]
    let meta: PaginationMetaDTO?

    func toDomain<T: Sendable>(_ transform: (Item) -> T?) -> Paginated<T> {
        Paginated(
            items: data.compactMap(transform),
            page: meta?.page ?? 1,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: meta?.totalPages ?? 1,
            hasMore: meta?.hasMore ?? false
        )
    }
}

// MARK: - Genre

/// Covers both `SONG_RESPONSE_SHAPE.md`'s embedded `primaryGenre`
/// (`{ name, image, imageVariants }`, no `id`) and the fuller standalone
/// shape `getGenreFromJson` (`lib/models/genre.dart`) parses.
struct GenreDTO: Decodable, Sendable {
    let id: String?
    let name: String?
    let image: String?
    let imageVariants: String?
    let type: String?
    let songsCount: Int?
    let playlistsCount: Int?
    let searchCount: Int?
}

extension GenreDTO {
    func toDomain() -> Genre {
        Genre(
            genreId: id,
            name: sanitized(name),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            type: sanitized(type),
            songsCount: songsCount,
            playlistsCount: playlistsCount,
            searchCount: searchCount
        )
    }
}

/// `getUserAppInitData` (`dashboard.controller.js`) → `/dashboard/init`'s
/// `genres` key: `prisma.genre.findMany({ where: { isActive: true } })` with
/// no `select` clause, i.e. full rows — the endpoint's own OpenAPI doc
/// comment under-documents this as `{id, name}` only, a stale doc (same
/// pattern already seen elsewhere in this backend), not the real shape.
/// Decoding through the existing all-optional `GenreDTO` is safe regardless.
struct DashboardInitGenresDTO: Decodable, Sendable {
    let genres: [GenreDTO]
}

/// `getGenreSongs` (`genre.controller.js:102-172`) → `/genre/songs/:genreId`:
/// same older `{meta: {count, page, perPage, totalPages}, data}` shape as
/// `CreatorSongsResponseDTO` — no `hasMore` field, derived below exactly the
/// same way.
struct GenreSongsResponseDTO: Decodable, Sendable {
    let data: [SongDTO]
    let meta: LegacyPaginationMetaDTO?
}

extension GenreSongsResponseDTO {
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

// MARK: - Creator

/// Covers both of `SONG_RESPONSE_SHAPE.md`'s Creator shapes (list-embedded:
/// `image`/`imageVariants`/`name`/`displayName`; detail: adds `id`/`email`/
/// `bio`/`followersCount`/`followers`) plus the extra fields
/// `getCreatorFromJson` (`lib/models/creator.dart`) reads for a standalone
/// creator-profile fetch (mobile/username/link/band/isActive/the
/// per-content-type counters/timestamps) — all fields optional so any one
/// shape decodes cleanly through the fields it actually sent.
struct CreatorDTO: Decodable, Sendable {
    let id: String?
    let name: String?
    let displayName: String?
    let image: String?
    let imageVariants: String?
    let bio: String?
    let email: String?
    let mobile: String?
    let username: String?
    let link: String?
    let band: String?
    let isActive: Bool?
    let createdAt: String?
    let updatedAt: String?

    let followersCount: Int?
    /// `getCreatorFromJson` reads these from `activeSongsCount`/
    /// `activeEpisodeCount`/`activeMusicCount` — a genuine request/response
    /// field-name asymmetry already present in Dart, not ported "fixed".
    let activeSongsCount: Int?
    let activeEpisodeCount: Int?
    let activeMusicCount: Int?
    let playlistsCount: Int?
    let albumsCount: Int?
    let seasonsCount: Int?

    /// Detail view only — presence (not emptiness) of each entry is what
    /// matters, so an empty-object marker is enough per entry.
    let followers: [EmptyMarkerDTO]?
}

extension CreatorDTO {
    func toDomain() -> Creator {
        Creator(
            creatorId: id,
            name: sanitized(name),
            displayName: sanitized(displayName),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            bio: sanitized(bio),
            email: sanitized(email),
            mobile: sanitized(mobile),
            username: sanitized(username),
            link: sanitized(link),
            band: sanitized(band),
            isActive: isActive,
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt),
            followersCount: followersCount,
            songsCount: activeSongsCount,
            episodeCount: activeEpisodeCount,
            musicCount: activeMusicCount,
            playlistsCount: playlistsCount,
            albumsCount: albumsCount,
            seasonsCount: seasonsCount,
            isFollowing: followers.map { !$0.isEmpty }
        )
    }
}

/// Decodes any JSON object while reading none of its fields — enough to
/// confirm an entry exists, which is all `favoritedBy`/`followers` are
/// ever used for (`isNotEmpty`, never a field on the entry itself).
struct EmptyMarkerDTO: Decodable, Sendable {}

// MARK: - Song

struct SongAudioURLsDTO: Decodable, Sendable {
    let original: String?
    let low: String?
    let standard: String?
    let high: String?
}

/// `playlists[].playlist.title` (`SONG_RESPONSE_SHAPE.md`'s "Nested
/// Objects" table: "playlist names only").
struct SongPlaylistRefDTO: Decodable, Sendable {
    struct Inner: Decodable, Sendable { let title: String? }
    let playlist: Inner?
}

/// One `songPrimaryArtists` row. List view sends `{ name }`; detail view
/// adds `creatorId`/`creator` — all optional so either shape decodes.
struct SongArtistRefDTO: Decodable, Sendable {
    let creatorId: String?
    let name: String?
    let creator: CreatorDTO?
}

struct FavoritedByEntryDTO: Decodable, Sendable {
    let songId: String?
}

struct LyricsTranscriptDTO: Decodable, Sendable {
    let id: String?
    let startTime: Double?
    let endTime: Double?
    let text: String?
}

struct SongCreditDTO: Decodable, Sendable {
    let role: String?
    let name: String?
    let category: String?
}

struct SongDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let type: String?

    let image: String?
    let imageVariants: String?
    let rectangleImage: String?
    let rectangleImageVariants: String?

    let audioFile: String?
    let audioVariants: String?
    let audioUrls: SongAudioURLsDTO?

    let duration: Int?
    let language: String?
    let releaseDate: String?

    let plays: Int?
    let likes: Int?
    let shares: Int?
    let downloads: Int?

    let writers: String?
    let primaryArtists: String?
    let featuredArtists: String?
    let isrcCode: String?
    let copyrightYear: Int?
    let productionYear: Int?
    let copyrightOwners: String?

    let songStatus: String?
    let reviewStatus: String?
    let processingStatus: String?
    let isScheduled: Bool?

    let dominantColor: String?
    let vibrantColor: String?
    let darkVibrantColor: String?
    let lightVibrantColor: String?
    let mutedColor: String?
    let onColor: String?
    let isDark: Bool?
    let gradient: [String]?

    let createdAt: String?
    let updatedAt: String?

    let creator: CreatorDTO?
    let primaryGenre: GenreDTO?
    let playlists: [SongPlaylistRefDTO]?
    let songPrimaryArtists: [SongArtistRefDTO]?
    let favoritedBy: [FavoritedByEntryDTO]?

    let transcripts: [LyricsTranscriptDTO]?
    let songCredits: [SongCreditDTO]?
}

extension SongDTO {
    /// `song.dart`'s `_primaryArtistsFromJson`: the legacy `primaryArtists`
    /// string when it actually holds a value, else the structured
    /// `songPrimaryArtists[].name` joined by `dotSign` (`" • "`). Newer uploads
    /// credit artists only through the relation and leave the legacy column
    /// null (or the literal "null"), so reading the column alone left the mini
    /// player / full player / lock-screen subtitle blank for those songs.
    private var resolvedPrimaryArtists: String? {
        if let legacy = sanitized(primaryArtists) { return legacy }
        let names = (songPrimaryArtists ?? []).compactMap { sanitized($0.name) }
        return names.isEmpty ? nil : names.joined(separator: " \u{2022} ")
    }

    func toDomain() -> Song {
        Song(
            id: id,
            title: sanitized(title),
            description: sanitized(description),
            type: sanitized(type),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            rectangleImage: sanitized(rectangleImage),
            rectangleImageVariants: sanitized(rectangleImageVariants),
            audioFile: sanitized(audioFile),
            audioVariants: sanitized(audioVariants),
            audioUrls: SongAudioURLs(
                original: audioUrls?.original.flatMap(URL.init(string:)),
                low: audioUrls?.low.flatMap(URL.init(string:)),
                standard: audioUrls?.standard.flatMap(URL.init(string:)),
                high: audioUrls?.high.flatMap(URL.init(string:))
            ),
            duration: duration,
            language: sanitized(language),
            releaseDate: Date.parseFlexibleISO8601(releaseDate),
            plays: plays,
            likes: likes,
            shares: shares,
            downloads: downloads,
            writers: sanitized(writers),
            primaryArtists: resolvedPrimaryArtists,
            featuredArtists: sanitized(featuredArtists),
            isrcCode: sanitized(isrcCode),
            copyrightYear: copyrightYear,
            productionYear: productionYear,
            copyrightOwners: sanitized(copyrightOwners),
            songStatus: sanitized(songStatus),
            reviewStatus: sanitized(reviewStatus),
            processingStatus: sanitized(processingStatus),
            isScheduled: isScheduled,
            dominantColor: sanitized(dominantColor),
            vibrantColor: sanitized(vibrantColor),
            darkVibrantColor: sanitized(darkVibrantColor),
            lightVibrantColor: sanitized(lightVibrantColor),
            mutedColor: sanitized(mutedColor),
            onColor: sanitized(onColor),
            isDark: isDark,
            gradient: gradient,
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt),
            creator: creator?.toDomain(),
            primaryGenre: primaryGenre?.toDomain(),
            playlistTitles: (playlists ?? []).compactMap { sanitized($0.playlist?.title) },
            songPrimaryArtists: (songPrimaryArtists ?? []).map {
                SongArtistRef(creatorId: $0.creatorId, name: sanitized($0.name), creator: $0.creator?.toDomain())
            },
            transcripts: transcripts.map { rows in
                rows.compactMap { row -> LyricsTranscript? in
                    guard let id = row.id else { return nil }
                    return LyricsTranscript(
                        id: id,
                        startTime: row.startTime ?? 0,
                        endTime: row.endTime ?? 0,
                        text: sanitized(row.text)
                    )
                }
            },
            songCredits: songCredits.map { rows in
                rows.map {
                    SongCredit(role: sanitized($0.role), name: sanitized($0.name), category: sanitized($0.category))
                }
            },
            isFavorited: !(favoritedBy ?? []).isEmpty
        )
    }
}

// MARK: - Playlist (Album / company / creator playlists)

/// `CompanyPlaylist` (`lib/models/company_playlist.dart`) — also how the
/// server represents an "Album" (`type == "album"`).
struct CompanyPlaylistDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let image: String?
    let imageVariants: String?
    let type: String?
    let language: String?
    let visibility: String?
    let rank: Int?
    let songsCount: Int?
    let activeSongsCount: Int?
    let createdAt: String?
    let updatedAt: String?
    /// `similarPlaylist` rows only — see `Playlist.isSeed`.
    let isSeed: Bool?
}

extension CompanyPlaylistDTO {
    func toDomain() -> Playlist {
        Playlist(
            id: id,
            title: sanitized(title) ?? "",
            description: sanitized(description),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            type: sanitized(type),
            visibility: sanitized(visibility),
            language: sanitized(language),
            songsCount: songsCount ?? activeSongsCount,
            duration: nil,
            rank: rank,
            owner: .company,
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt),
            isSeed: isSeed ?? false
        )
    }
}

/// `CreatorPlaylist` (`lib/models/playlist.dart`) — the `playlists`
/// viewType rail, e.g. "Top Albums" per `car_play_service.dart`'s comment.
struct CreatorPlaylistRefDTO: Decodable, Sendable {
    let name: String?
}

struct CreatorPlaylistDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let image: String?
    let imageVariants: String?
    let type: String?
    let visibility: String?
    let creatorId: String?
    let creator: CreatorPlaylistRefDTO?
    let songsCount: Int?
    let activeSongsCount: Int?
    let duration: Int?
    let createdAt: String?
    let updatedAt: String?
}

extension CreatorPlaylistDTO {
    func toDomain() -> Playlist {
        Playlist(
            id: id,
            title: sanitized(title) ?? "",
            description: sanitized(description),
            image: sanitized(image),
            imageVariants: sanitized(imageVariants),
            type: sanitized(type),
            visibility: sanitized(visibility),
            language: nil,
            songsCount: songsCount ?? activeSongsCount,
            duration: duration,
            rank: nil,
            owner: .creator(id: creatorId, name: sanitized(creator?.name)),
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt),
            isSeed: false
        )
    }
}

// MARK: - Recent (mixed) rail

struct RecentContentItemDTO: Decodable, Sendable {
    struct SongRef: Decodable, Sendable {
        let id: String?
        let type: String?
        let rectangleImage: String?
        let rectangleImageVariants: String?
    }
    struct EntityRef: Decodable, Sendable {
        let type: String?
    }

    let id: String?
    let itemType: String?
    let entityId: String?
    let title: String?
    let subtitle: String?
    let image: String?
    let imageVariants: String?
    let playedAt: String?
    let song: SongRef?
    let entity: EntityRef?
}

extension RecentContentItemDTO {
    /// Ports `RecentItem.fromJson`'s image-column swap: a `song` card whose
    /// resolved content type is an episode prefers the rectangle column,
    /// since the flat `image` field the server sends for this rail is
    /// always the square one.
    func toDomain() -> RecentContentItem {
        let itemType = sanitized(itemType) ?? "song"
        let contentType = sanitized(song?.type) ?? sanitized(entity?.type)

        var resolvedImage = sanitized(image)
        var resolvedImageVariants = sanitized(imageVariants)
        if itemType == "song", contentType == "episode",
           let rectangle = sanitized(song?.rectangleImage) {
            resolvedImage = rectangle
            resolvedImageVariants = sanitized(song?.rectangleImageVariants)
        }

        return RecentContentItem(
            id: id ?? "",
            itemType: itemType,
            entityId: sanitized(entityId),
            title: sanitized(title),
            subtitle: sanitized(subtitle),
            image: resolvedImage,
            imageVariants: resolvedImageVariants,
            playedAt: Date.parseFlexibleISO8601(playedAt),
            songId: sanitized(song?.id),
            contentType: contentType
        )
    }
}

// MARK: - Shared helpers

/// Treats the literal strings `"null"`/`"undefined"` — which `song.dart`'s
/// own `_isNullLiteral` says "leak in from some backend serializers" — the
/// same as a genuinely absent value, everywhere a DTO hands a string to a
/// domain entity. Applied in the mapper (on already-typed `String?`
/// values) rather than via custom `Decodable` parsing, so every DTO above
/// keeps plain compiler-synthesized decoding — safer to get right by
/// inspection than hand-written `Decoder` calls with no compiler to check
/// them against.
private func sanitized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "undefined" { return nil }
    return trimmed
}
