import Foundation

/// Ports `Genre`/`getGenreFromJson` (`lib/models/genre.dart`) — a song's
/// `primaryGenre`, and the standalone genre-browse list. Counters are
/// present on the browse-list shape and absent (nil) when a genre only
/// rides along embedded in a `Song` (`SONG_RESPONSE_SHAPE.md`'s
/// `primaryGenre`, `{ name, image, imageVariants }` only — no `id` at all
/// in that embedded shape, hence `genreId` being optional here too).
struct Genre: Sendable, Equatable, Identifiable {
    let genreId: String?
    let name: String?
    let image: String?
    let imageVariants: String?
    let type: String?
    let songsCount: Int?
    let playlistsCount: Int?
    let searchCount: Int?

    /// Falls back to `name` (mirrors `LanguageOption`'s same fallback,
    /// `App/Domain/Entities/LanguageOption.swift`) since the embedded shape
    /// has no `id` for `Identifiable` to key off.
    var id: String { genreId ?? name ?? "" }
}
