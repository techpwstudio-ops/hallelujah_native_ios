import Foundation

/// Pre-signed CloudFront playback URLs (`SONG_RESPONSE_SHAPE.md`'s
/// `audioUrls`). Expire ~3 hours after issue — never persist these once a
/// local cache exists (no such cache exists yet; noted for whichever future
/// task adds one, matching the shape doc's own "Never store `audioUrls` in
/// Realm" rule).
struct SongAudioURLs: Sendable, Equatable {
    /// Present only when `audioVariants` is nil (not yet optimized).
    let original: URL?
    let low: URL?
    let standard: URL?
    let high: URL?

    var isEmpty: Bool { original == nil && low == nil && standard == nil && high == nil }
}

/// The original upload behind an episode's silent video (`videoVariantsMeta.source`). Every field is
/// optional: the backend probes the file and a probe can miss a value.
struct VideoSourceInfo: Sendable, Equatable {
    /// ffprobe's `codec_name`: `h264`, `hevc`, `vp9`, `av1`, `prores`, ...
    let codec: String?
    /// Display dimensions, so a rotated phone video reports its upright size.
    let width: Int?
    let height: Int?
    let fps: Double?
    let bitrate: Int?

    /// The shorter side, which names a rung (`1080p` is 1080 on the short side, vertical or not).
    /// `nil` when either dimension is missing or not positive.
    var shortSide: Int? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return min(width, height)
    }
}

/// One transcript line (`GET /api/songs/:id`'s `transcripts`, detail only).
struct LyricsTranscript: Sendable, Equatable, Identifiable {
    let id: String
    let startTime: Double
    let endTime: Double
    let text: String?
    /// The language of the server row the line came from (`LyricsTranscript.language`, e.g.
    /// "English"); `nil` for a line in the old flat form.
    let language: String?

    /// How two languages are compared: case and surrounding spaces ignored, `nil` as "".
    static func languageKey(_ language: String?) -> String {
        (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Array where Element == LyricsTranscript {
    /// One language's lines out of `Song.transcripts`, which holds every language the song has: the
    /// `preferred` one (the user's Bible language) when the song has it, otherwise the first, as
    /// Flutter's `lyrics_ui.dart` picks. Lines with no language all count as one language.
    func inPreferredLanguage(_ preferred: String?) -> [LyricsTranscript] {
        guard let first else { return [] }
        let preferredKey = LyricsTranscript.languageKey(preferred)
        let hasPreferred = preferred != nil && contains { LyricsTranscript.languageKey($0.language) == preferredKey }
        let chosen = hasPreferred ? preferredKey : LyricsTranscript.languageKey(first.language)
        return filter { LyricsTranscript.languageKey($0.language) == chosen }
    }
}

/// One production credit (`GET /api/songs/:id`'s `songCredits`, detail only).
struct SongCredit: Sendable, Equatable {
    let role: String?
    let name: String?
    /// Grouping heading for the credits sheet (`SongCredit.category`,
    /// `SongRepositoryModel.dart`); absent on older rows.
    let category: String?
}

/// One row of `songPrimaryArtists`. List view: `{ name }` only. Detail view
/// adds `creatorId` and a nested `creator` (`image`/`imageVariants`/
/// `followers` — this per-artist `Creator` is deliberately reused rather
/// than a bespoke sub-shape, since its fields are a strict subset of
/// `Creator`'s own list-embedded shape) — all optional here to cover both
/// without two types, same reasoning as `Creator`'s own list/detail split.
struct SongArtistRef: Sendable, Equatable {
    let creatorId: String?
    let name: String?
    let creator: Creator?
}

/// Ports `Song`/`getSongFromJson` (`lib/models/song.dart`), grounded in
/// `SONG_RESPONSE_SHAPE.md` (the written spec) rather than the Realm model
/// directly — the Realm model flattens/denormalizes the wire shape for
/// local caching (e.g. `creatorName`/`creatorImage` copied onto the song
/// row); this type keeps the wire shape's own nesting (`creator`,
/// `primaryGenre`) instead, since there is no local content cache yet for
/// flattening to serve.
struct Song: Sendable, Equatable, Identifiable {
    let id: String
    let title: String?
    let description: String?
    /// `"music"` or `"episode"` — kept as the raw server string (like Dart's
    /// own `String? type`) rather than an enum, so an unrecognized future
    /// value degrades to "not an episode" instead of failing to decode.
    let type: String?

    let image: String?
    let imageVariants: String?
    let rectangleImage: String?
    let rectangleImageVariants: String?
    let audioFile: String?
    let audioVariants: String?
    let audioUrls: SongAudioURLs

    let duration: Int?
    let language: String?
    let releaseDate: Date?

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

    let createdAt: Date?
    let updatedAt: Date?

    let creator: Creator?
    let primaryGenre: Genre?
    /// Playlist titles this song appears on (`playlists[].playlist.title`).
    let playlistTitles: [String]

    /// Detail view only (`GET /api/songs/:id`).
    let songPrimaryArtists: [SongArtistRef]
    let transcripts: [LyricsTranscript]?
    let songCredits: [SongCredit]?

    /// `favoritedBy.isNotEmpty` — the API filters that list to the current
    /// user, so any entry at all means "favorited by me".
    let isFavorited: Bool

    /// Chapters, speakers and transcript reference for an episode, from the
    /// detail call only (`nil` for music and for list rows). `var` with a
    /// default, not `let`: a `let` default would drop it from the memberwise
    /// initializer, and five call sites rely on that initializer. Not persisted
    /// with the song (I3); its signed transcript URL expires like `audioUrls`.
    var episodeTimeline: EpisodeTimeline? = nil

    /// The episode's silent video, a storage key served through the proxy like `audioFile`
    /// (`SILENT_VIDEO_MODE_PLAN.md`). `var` with a default for the same reason as
    /// `episodeTimeline`. It may carry sound when a creator uploaded audio and video separately,
    /// so the player always mutes it.
    var videoFile: String? = nil

    /// The encoded renditions of `videoFile`, beside it in storage, as the wire sends them: a comma
    /// list such as `"480p.mp4,720p.mp4,1080p.mp4"` holding only the rungs that exist. `nil` until the
    /// backend has processed the episode, and then it plays `videoFile` as before. Read it through
    /// `VideoQualitySelector`, never by hand.
    var videoVariants: String? = nil

    /// What the original `videoFile` is (`videoVariantsMeta.source`): its codec and size, which decide
    /// whether this device can play it. `nil` when the backend did not say.
    var videoSource: VideoSourceInfo? = nil

    /// Whether there is a video to switch to. Not gated on `type`, as in Flutter's `Song.hasVideo`.
    var hasVideo: Bool { !(videoFile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    var isEpisode: Bool { type == "episode" }

    /// `SONG_RESPONSE_SHAPE.md`'s "Audio URL Rules": which square/rectangle
    /// column a card should draw from. Ports `Song.image`
    /// (`type == 'music' ? imagePrivate : rectangleImagePrivate`).
    var displayImage: String? { isEpisode ? rectangleImage : image }
    var displayImageVariants: String? { isEpisode ? rectangleImageVariants : imageVariants }

    /// `Song.widthRatio` — square art for music, 16:9 for an episode.
    var displayAspectRatio: Double { isEpisode ? 16.0 / 9.0 : 1.0 }
}

extension Song {
    /// `primaryArtists` and `featuredArtists` joined by Dart's `dotSign`
    /// (`" • "`, `lib/constants/strings.dart:22`); empty when neither is set.
    /// The mini player, full player and lock screen all show this line.
    var artistLine: String {
        [primaryArtists, featuredArtists]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    /// A copy with just `isFavorited` flipped. `Song` is otherwise fully
    /// immutable — `RemoteFavouriteRepository`'s toggle endpoint doesn't
    /// return a song-shaped payload to re-decode (T44; confirmed directly
    /// against `songs.controller.js`'s `toggleSongFavorite`), so every call
    /// site that reflects a toggle's result (`AudioEngine.currentSong`, a
    /// favourites-list row) rebuilds its own local copy through this instead.
    func withFavorited(_ isFavorited: Bool) -> Song {
        Song(
            id: id,
            title: title,
            description: description,
            type: type,
            image: image,
            imageVariants: imageVariants,
            rectangleImage: rectangleImage,
            rectangleImageVariants: rectangleImageVariants,
            audioFile: audioFile,
            audioVariants: audioVariants,
            audioUrls: audioUrls,
            duration: duration,
            language: language,
            releaseDate: releaseDate,
            plays: plays,
            likes: likes,
            shares: shares,
            downloads: downloads,
            writers: writers,
            primaryArtists: primaryArtists,
            featuredArtists: featuredArtists,
            isrcCode: isrcCode,
            copyrightYear: copyrightYear,
            productionYear: productionYear,
            copyrightOwners: copyrightOwners,
            songStatus: songStatus,
            reviewStatus: reviewStatus,
            processingStatus: processingStatus,
            isScheduled: isScheduled,
            dominantColor: dominantColor,
            vibrantColor: vibrantColor,
            darkVibrantColor: darkVibrantColor,
            lightVibrantColor: lightVibrantColor,
            mutedColor: mutedColor,
            onColor: onColor,
            isDark: isDark,
            gradient: gradient,
            createdAt: createdAt,
            updatedAt: updatedAt,
            creator: creator,
            primaryGenre: primaryGenre,
            playlistTitles: playlistTitles,
            songPrimaryArtists: songPrimaryArtists,
            transcripts: transcripts,
            songCredits: songCredits,
            isFavorited: isFavorited,
            episodeTimeline: episodeTimeline,
            videoFile: videoFile,
            videoVariants: videoVariants,
            videoSource: videoSource
        )
    }
}
