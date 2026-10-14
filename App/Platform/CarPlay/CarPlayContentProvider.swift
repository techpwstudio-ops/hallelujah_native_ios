import Foundation

/// T49–T51 — everything CarPlay needs to *show*, fetched through the same
/// repositories the phone UI uses (same endpoints, same auth, same caches)
/// and mapped to `CarPlayRow`s. Replaces the Flutter host's `FlutterMethodChannel`
/// round-trips (`getHomeSections`, `getSongs`, `getGenres`, `getPlaylists`, …)
/// with direct calls — there is no second runtime to bridge to.
///
/// Every method is non-throwing: a failed fetch logs and returns an empty
/// result, which the controller renders as the template's own "nothing here"
/// row. CarPlay has no good surface for an error banner, and the Dart
/// delegate degraded the same way (`as? [[String: Any]] ?? []`).
@MainActor
final class CarPlayContentProvider {
    /// CarPlay renders at most this many rows per list; fetching beyond it is
    /// wasted network (`CPListTemplate.maximumItemCount` is the live limit,
    /// this is only the fetch-side ceiling so a huge library doesn't page
    /// through hundreds of songs on connect).
    static let maxFetchedRows = 100
    /// How many Home rails are built. Home has more rails than a driver will
    /// ever scroll; the phone UI remains the place for the long tail.
    static let maxHomeRails = 12
    /// Rails pre-hydrated by the layout call itself; the rest are fetched on
    /// demand below.
    static let homeHydratedSections = 6

    private let home: any HomeRepository
    private let creators: any CreatorRepository
    private let playlists: any PlaylistRepository
    private let userPlaylists: any UserPlaylistRepository
    private let genres: any GenreRepository
    private let favourites: any FavouriteRepository
    private let search: any SearchRepository
    private let downloads: DownloadEngine
    private let artwork: ArtworkURLResolver
    private let logger = AppLogger(category: .carPlay)

    init(container: DependencyContainer = .current) {
        home = container.resolve()
        creators = container.resolve()
        playlists = container.resolve()
        userPlaylists = container.resolve()
        genres = container.resolve()
        favourites = container.resolve()
        search = container.resolve()
        downloads = container.resolve()
        artwork = ArtworkURLResolver()
    }

    // MARK: - Home

    func homeRails() async -> [CarPlayRail] {
        let layout: HomeLayout?
        do {
            layout = try await home.fetchLayout(type: .all, withSections: Self.homeHydratedSections)
        } catch {
            logger.warning("CarPlay home layout failed (\(error)); falling back to cache")
            layout = await home.cachedLayout(type: .all)
        }
        guard let layout else { return [] }

        var hydrated: [String: ContentSection] = [:]
        for section in layout.hydrated where hydrated[section.id] == nil {
            hydrated[section.id] = section
        }

        let wanted = layout.placeholders.prefix(Self.maxHomeRails)
        let missing = wanted.filter {
            hydrated[$0.id] == nil
                && !layout.emptyUiIds.contains($0.id)
                && !layout.degradedUiIds.contains($0.id)
        }

        let fetched = await withTaskGroup(of: ContentSection?.self) { group -> [ContentSection] in
            for placeholder in missing {
                group.addTask { [home] in
                    guard let outcome = try? await home.fetchSection(type: .all, uiId: placeholder.id, page: 1),
                          case .loaded(let section) = outcome else { return nil }
                    return section
                }
            }
            var sections: [ContentSection] = []
            for await section in group {
                if let section { sections.append(section) }
            }
            return sections
        }
        for section in fetched { hydrated[section.id] = section }

        return wanted.compactMap { placeholder in
            guard let section = hydrated[placeholder.id] else { return nil }
            return rail(for: section)
        }
    }

    private func rail(for section: ContentSection) -> CarPlayRail? {
        let source = QueueAttribution(playerType: .home, id: section.id, title: section.title)
        let group: CarPlayRowGroup
        switch section.content {
        case .songs(let page):
            group = songGroup(page.items, source: source)
        case .creators(let page):
            group = CarPlayRowGroup(rows: page.items.map(creatorRow), songs: [], source: source)
        case .playlists(let page):
            group = CarPlayRowGroup(rows: page.items.map(playlistRow), songs: [], source: source)
        case .recentItems(let page):
            group = CarPlayRowGroup(rows: page.items.compactMap(recentRow), songs: [], source: source)
        case .unsupported(let viewType):
            // Same graceful skip `car_play_service.dart` logs for a viewType it doesn't map.
            logger.info("CarPlay skipping unrecognized viewType \(viewType)")
            return nil
        }
        guard !group.rows.isEmpty else { return nil }
        return CarPlayRail(id: section.id, title: section.title, viewType: section.viewType, group: group)
    }

    // MARK: - Recents

    /// The server's "Continue Your Journey" rail (`recent-all`), the same
    /// data the phone's Home rail shows. The Flutter delegate read a local
    /// `playback_sessions` table instead; the native app has no local
    /// playback-history table, and this rail is the server-side equivalent.
    func recentRows() async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .home, id: "recent-all", title: "")
        guard let outcome = try? await home.fetchSection(type: .all, uiId: "recent-all", page: 1),
              case .loaded(let section) = outcome,
              case .recentItems(let page) = section.content else {
            return .empty(source: source)
        }
        return CarPlayRowGroup(
            rows: Array(page.items.compactMap(recentRow).prefix(Self.maxFetchedRows)),
            songs: [],
            source: source
        )
    }

    /// A recent *song* card carries only an id — there is no song-by-id
    /// endpoint — so it is resolved by searching its title and picking the
    /// hit with the matching id. `nil` when the search doesn't surface it.
    func resolveSong(id: String, title: String) async -> Song? {
        guard !title.isEmpty,
              let results = try? await search.search(
                  query: title, filter: nil,
                  musicPage: 1, episodePage: 1, creatorPage: 1, playlistPage: 1,
                  userPlaylistId: nil
              ) else { return nil }
        return (results.music.items + results.episodes.items).first { $0.id == id }
    }

    // MARK: - Search tab (genres)

    /// `CPSearchTemplate` isn't granted to the audio entitlement, so the
    /// Search tab mirrors the phone Search page's landing state — Browse
    /// Genres — exactly as the Dart delegate did.
    func genreRows() async -> [CarPlayRow] {
        guard let fetched = try? await genres.fetchGenres() else { return [] }
        return fetched.compactMap { genre in
            guard let name = genre.name, !genre.id.isEmpty else { return nil }
            return CarPlayRow(
                id: "genre-\(genre.id)",
                title: name,
                subtitle: nil,
                artworkURL: artworkURL(path: genre.image, variants: genre.imageVariants),
                kind: .genre(id: genre.id)
            )
        }
    }

    func genreSongs(id: String, title: String) async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .genre, id: id, title: title)
        let songs = await fetchPages { page in try await self.genres.fetchSongs(genreID: id, page: page) }
        return songGroup(songs, source: source)
    }

    // MARK: - Library

    func likedSongs() async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .favourite, id: nil, title: "")
        let songs = await fetchPages { page in try await self.favourites.fetchFavouriteSongs(type: .all, page: page) }
        return songGroup(songs, source: source)
    }

    /// Completed downloads only. `DownloadTask` is a display snapshot (no
    /// `Song` cache survives a relaunch), so each row is rebuilt into a
    /// minimal playable `Song` — `AudioEngine.localFileURLProvider` resolves
    /// the local file by id, so no audio URLs are needed.
    func downloadedSongs() -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .download, id: nil, title: "")
        let completed = downloads.tasks.values
            .filter { $0.state == .completed && downloads.isDownloaded(songID: $0.songID) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maxFetchedRows)
        let songs = completed.map(Song.makeDownloadedSnapshot)
        return songGroup(songs, source: source)
    }

    /// Library → Playlists: company playlists (collected from the Home
    /// feed's playlist rails, as the Dart side aggregated them) followed by
    /// the user's own playlists, in one list.
    func allPlaylistRows() async -> [CarPlayRow] {
        async let companyRows = companyPlaylistRows()
        async let userRows = userPlaylistRows()
        return await companyRows + userRows
    }

    private func companyPlaylistRows() async -> [CarPlayRow] {
        var seen = Set<String>()
        var rows: [CarPlayRow] = []
        for rail in await homeRails() {
            for row in rail.group.rows {
                guard case .companyPlaylist(let id) = row.kind, seen.insert(id).inserted else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    private func userPlaylistRows() async -> [CarPlayRow] {
        guard let page = try? await userPlaylists.fetchPlaylists(page: 1) else { return [] }
        return page.items.map { playlist in
            CarPlayRow(
                id: "user-playlist-\(playlist.id)",
                title: playlist.title,
                subtitle: nil,
                artworkURL: artworkURL(path: playlist.image, variants: playlist.imageVariants),
                kind: .userPlaylist(id: playlist.id)
            )
        }
    }

    // MARK: - Pushed song lists

    func companyPlaylistSongs(id: String, title: String) async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .companyPlaylist, id: id, title: title)
        let songs = await fetchPages { page in
            try await self.playlists.fetchSongs(playlistId: id, owner: .company, page: page)
        }
        return songGroup(songs, source: source)
    }

    func creatorPlaylistSongs(id: String, title: String) async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .album, id: id, title: title)
        let songs = await fetchPages { page in
            try await self.playlists.fetchSongs(playlistId: id, owner: .creator(id: nil, name: nil), page: page)
        }
        return songGroup(songs, source: source)
    }

    func userPlaylistSongs(id: String, title: String) async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .userPlaylist, id: id, title: title)
        let songs = await fetchPages { page in
            try await self.userPlaylists.fetchSongs(playlistID: id, page: page).songs
        }
        return songGroup(songs, source: source)
    }

    func creatorSongs(id: String, title: String) async -> CarPlayRowGroup {
        let source = QueueAttribution(playerType: .creator, id: id, title: title)
        let songs = await fetchPages { page in
            try await self.creators.fetchSongs(creatorId: id, type: .all, page: page)
        }
        return songGroup(songs, source: source)
    }

    // MARK: - Mapping

    func songGroup(_ songs: [Song], source: QueueAttribution) -> CarPlayRowGroup {
        let rows = songs.enumerated().map { index, song in
            CarPlayRow(
                id: "song-\(song.id)",
                title: song.title ?? "",
                subtitle: Self.artistLine(for: song),
                artworkURL: artworkURL(path: song.displayImage, variants: song.displayImageVariants),
                kind: .song(index: index)
            )
        }
        return CarPlayRowGroup(rows: rows, songs: songs, source: source)
    }

    private func creatorRow(_ creator: Creator) -> CarPlayRow {
        CarPlayRow(
            id: "creator-\(creator.id)",
            title: creator.displayName ?? creator.name ?? "",
            subtitle: nil,
            artworkURL: artworkURL(path: creator.image, variants: creator.imageVariants),
            kind: .creator(id: creator.creatorId ?? creator.id)
        )
    }

    private func playlistRow(_ playlist: Playlist) -> CarPlayRow {
        let kind: CarPlayRow.Kind = switch playlist.owner {
        case .company: .companyPlaylist(id: playlist.id)
        case .creator: .creatorPlaylist(id: playlist.id)
        }
        return CarPlayRow(
            id: "playlist-\(playlist.id)",
            title: playlist.title,
            subtitle: nil,
            artworkURL: artworkURL(path: playlist.image, variants: playlist.imageVariants),
            kind: kind
        )
    }

    private func recentRow(_ item: RecentContentItem) -> CarPlayRow? {
        let target = item.entityId ?? item.id
        let kind: CarPlayRow.Kind
        switch item.itemType {
        case "song":
            guard let songID = item.songId ?? item.entityId else { return nil }
            kind = .recentSong(songID: songID)
        case "creator": kind = .creator(id: target)
        case "companyPlaylist": kind = .companyPlaylist(id: target)
        case "album", "season": kind = .creatorPlaylist(id: target)
        case "userPlaylist": kind = .userPlaylist(id: target)
        default: return nil
        }
        return CarPlayRow(
            id: "recent-\(item.id)",
            title: item.title ?? "",
            subtitle: item.subtitle,
            artworkURL: artworkURL(path: item.image, variants: item.imageVariants),
            kind: kind
        )
    }

    private func artworkURL(path: String?, variants: String?) -> URL? {
        artwork.resolve(path: path, variant: .sm, allowedVariants: variants)
    }

    private static func artistLine(for song: Song) -> String? {
        let parts = [song.primaryArtists, song.featuredArtists].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Pages through a paginated endpoint until `maxFetchedRows` or the end.
    private func fetchPages<Item: Sendable>(
        _ fetch: (Int) async throws -> Paginated<Item>
    ) async -> [Item] {
        var items: [Item] = []
        var page = 1
        while items.count < Self.maxFetchedRows {
            guard let result = try? await fetch(page) else { break }
            items += result.items
            guard result.hasMore, !result.items.isEmpty else { break }
            page += 1
        }
        return Array(items.prefix(Self.maxFetchedRows))
    }
}

extension Song {
    /// A minimal playable `Song` rebuilt from a `DownloadTask`'s display
    /// snapshot. Only the fields a CarPlay row / Now Playing needs are set;
    /// the audio source comes from the local file, never from `audioUrls`.
    static func makeDownloadedSnapshot(_ task: DownloadTask) -> Song {
        Song(
            id: task.songID, title: task.songTitle, description: nil, type: task.songType,
            image: task.songArtworkPath, imageVariants: task.songArtworkVariants,
            rectangleImage: task.songArtworkPath, rectangleImageVariants: task.songArtworkVariants,
            audioFile: nil, audioVariants: nil,
            audioUrls: SongAudioURLs(original: nil, low: nil, standard: nil, high: nil),
            duration: task.songDurationSeconds, language: nil, releaseDate: nil,
            plays: nil, likes: nil, shares: nil, downloads: nil,
            writers: nil, primaryArtists: nil, featuredArtists: nil, isrcCode: nil,
            copyrightYear: nil, productionYear: nil, copyrightOwners: nil,
            songStatus: nil, reviewStatus: nil, processingStatus: nil, isScheduled: nil,
            dominantColor: nil, vibrantColor: nil, darkVibrantColor: nil, lightVibrantColor: nil,
            mutedColor: nil, onColor: nil, isDark: nil, gradient: nil,
            createdAt: nil, updatedAt: nil,
            creator: nil, primaryGenre: nil, playlistTitles: [],
            songPrimaryArtists: [], transcripts: nil, songCredits: nil,
            isFavorited: false
        )
    }
}
