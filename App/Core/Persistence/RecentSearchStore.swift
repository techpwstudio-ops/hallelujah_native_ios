import Foundation

/// A minimal, persisted stand-in for `Song` — just enough to render a
/// history row and, on tap, rebuild something `QueueController.play` can
/// take. Dart never needs this: `SongSearchItem` re-reads the tapped song
/// live from Realm on every render (and renders nothing at all if that
/// lookup misses — a real, accepted Dart quirk). There is no equivalent
/// shared local content cache here for a lightweight `id`-only pointer to
/// resolve against, so `RecentSearchStore` persists a real snapshot instead.
///
/// Deliberately not `Song` itself made `Codable`: `Song.audioUrls`
/// (`Song.swift`'s own doc comment) must never be persisted, and a
/// dedicated snapshot type — one with no `audioUrls` field to accidentally
/// round-trip — keeps that true by construction rather than by discipline.
struct RecentSongSnapshot: Sendable, Equatable, Codable, Identifiable {
    let id: String
    let title: String?
    let type: String?
    let image: String?
    let imageVariants: String?
    let rectangleImage: String?
    let rectangleImageVariants: String?
    let primaryArtists: String?
    let featuredArtists: String?
    /// Stable S3 keys, not pre-signed URLs — safe to persist indefinitely,
    /// unlike `audioUrls`. See `asSong`.
    let audioFile: String?
    let audioVariants: String?
}

extension RecentSongSnapshot {
    init(song: Song) {
        id = song.id
        title = song.title
        type = song.type
        image = song.image
        imageVariants = song.imageVariants
        rectangleImage = song.rectangleImage
        rectangleImageVariants = song.rectangleImageVariants
        primaryArtists = song.primaryArtists
        featuredArtists = song.featuredArtists
        audioFile = song.audioFile
        audioVariants = song.audioVariants
    }

    /// Reconstructs a minimal, playable `Song` for a history-row tap.
    /// `audioUrls` is deliberately empty — `AudioSourceResolver.resolve`
    /// falls through to its proxy tier automatically whenever no presigned
    /// URL checks out, using exactly the `audioFile`/`audioVariants` pair
    /// this type does persist, so playback from history works through the
    /// same resolver every other song uses, with no special-casing.
    var asSong: Song {
        Song(
            id: id,
            title: title,
            description: nil,
            type: type,
            image: image,
            imageVariants: imageVariants,
            rectangleImage: rectangleImage,
            rectangleImageVariants: rectangleImageVariants,
            audioFile: audioFile,
            audioVariants: audioVariants,
            audioUrls: SongAudioURLs(original: nil, low: nil, standard: nil, high: nil),
            duration: nil,
            language: nil,
            releaseDate: nil,
            plays: nil,
            likes: nil,
            shares: nil,
            downloads: nil,
            writers: nil,
            primaryArtists: primaryArtists,
            featuredArtists: featuredArtists,
            isrcCode: nil,
            copyrightYear: nil,
            productionYear: nil,
            copyrightOwners: nil,
            songStatus: nil,
            reviewStatus: nil,
            processingStatus: nil,
            isScheduled: nil,
            dominantColor: nil,
            vibrantColor: nil,
            darkVibrantColor: nil,
            lightVibrantColor: nil,
            mutedColor: nil,
            onColor: nil,
            isDark: nil,
            gradient: nil,
            createdAt: nil,
            updatedAt: nil,
            creator: nil,
            primaryGenre: nil,
            playlistTitles: [],
            songPrimaryArtists: [],
            transcripts: nil,
            songCredits: nil,
            isFavorited: false
        )
    }
}

/// One persisted row. The same 3-bucket shape as Dart's Realm key
/// (`"${uiItemType.name}_$modelId"`, `SearchHistoryModel`/
/// `addToSearchHistory` in `lib/blocs/search/bloc.dart`) — `songs` covers
/// both music and episode, `creator`, `playlists`. `Codable` synthesizes
/// automatically here since every associated value already conforms.
enum RecentSearchEntry: Sendable, Equatable, Codable, Identifiable {
    case song(RecentSongSnapshot)
    case creator(SearchCreatorResult)
    case playlist(SearchPlaylistResult)

    var id: String {
        switch self {
        case .song(let snapshot): "songs_\(snapshot.id)"
        case .creator(let creator): "creator_\(creator.id)"
        case .playlist(let playlist): "playlists_\(playlist.compositeID)"
        }
    }
}

/// T40 — ports the recently-tapped-result list `RecentSearches` renders
/// when the search field is empty (`content_search_page.dart`), backed by
/// `SearchHistoryModel` there. `record`/`remove`/`clearAll` mirror
/// `addToSearchHistory`/`removeSearchHistory`/`clearSearchHistory`
/// (`content_search_page.dart`).
///
/// `@MainActor @Observable`, not an `actor` (contrast `HomeFeedCache`,
/// which is read once per screen load via `async` calls): the "Recent"
/// list is bound directly into `SearchViewModel`'s reactive state and
/// re-rendered live as it mutates (add on tap, remove on swipe, Clear All),
/// the same reactive-observable shape `PlaylistProgressStore` uses.
///
/// Not wired into `SignOutSignal`'s `onLogout` closure (`AppComposition
/// .installRuntime()`), unlike `currentUserStore` there — matching Dart:
/// `RealmService.logout()` (`realm_service.dart:90-115`) explicitly
/// `deleteAll`s `Song`/`Creator`/`UserPlaylist`/`Genre`/etc. on sign-out, and
/// documents several deliberate exclusions in its own comments (Bible
/// downloads, `FavouriteCreator`) — `SearchHistoryModel` isn't in that list
/// at all, exclusion by omission rather than by an explicit kept-comment,
/// but the list is otherwise exhaustive enough that leaving search history
/// untouched across accounts on the same device reads as intentional, not a
/// gap. This store follows that same behavior.
@MainActor
@Observable
final class RecentSearchStore {
    /// One persisted row plus its own `searchDateTime` — `RecentSearches`'s
    /// query (`content_search_page.dart`) is literally `SORT(searchDateTime
    /// DESC) LIMIT(10)`, a timestamp sort, not insertion order; `entries`
    /// below ports that same sort at read time rather than assuming
    /// write-order already matches it.
    private struct Record: Sendable, Equatable, Codable {
        let entry: RecentSearchEntry
        let recordedAt: Date
    }

    private static let storageKey = "recent_search"
    /// `LIMIT(10)`. Dart caps at query time; this caps after every write
    /// instead — same effect, since nothing reads `records` except through
    /// `entries`.
    private static let maxEntries = 10

    private var records: [Record] = []
    private let keyValueStore: any KeyValueStoring
    private let clock: any ClockProviding

    /// Most-recent-first, matching `SORT(searchDateTime DESC)` exactly.
    var entries: [RecentSearchEntry] {
        records.sorted { $0.recordedAt > $1.recordedAt }.map(\.entry)
    }

    init(keyValueStore: any KeyValueStoring, clock: any ClockProviding) {
        self.keyValueStore = keyValueStore
        self.clock = clock
        if let data = keyValueStore.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        }
    }

    /// Upsert: an entry already present under the same `id` is replaced
    /// with the fresh snapshot and a fresh `recordedAt`, matching Dart's own
    /// keyed Realm upsert (`realm.add(..., update: true)` — a repeat tap
    /// updates in place and re-sorts to the top rather than duplicating).
    ///
    /// No equivalent of Dart's `verifyRecentSearches()` (which prunes a
    /// history row once its underlying Realm object is gone): every entry
    /// here is a self-contained snapshot, not a pointer into a live content
    /// cache, so there is nothing for it to go stale against.
    func record(_ entry: RecentSearchEntry) {
        records.removeAll { $0.entry.id == entry.id }
        records.append(Record(entry: entry, recordedAt: clock.now()))
        if records.count > Self.maxEntries {
            records = Array(records.sorted { $0.recordedAt > $1.recordedAt }.prefix(Self.maxEntries))
        }
        persist()
    }

    /// The per-row clear (×) button.
    func remove(id: String) {
        records.removeAll { $0.entry.id == id }
        persist()
    }

    /// The "Clear All" button.
    func clearAll() {
        records.removeAll()
        keyValueStore.removeValue(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        keyValueStore.setData(data, forKey: Self.storageKey)
    }
}
