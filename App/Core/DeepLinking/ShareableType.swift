/// Mirrors the server's `ShareableType` (`lib/services/deep_link_service.dart`).
/// Backed by the raw string so decoding matches Dart's own `.name`-string
/// comparison — a case MISSING here is a destination the app silently
/// cannot open.
///
/// `playlist` is the creator-owned Playlist (an album OR a season — one
/// model, one screen), a different table from both `companyPlaylist` and
/// `userPlaylist`. `bibleVerse` is an arbitrary verse shared from the Bible
/// reader, distinct from `verseOfDay`, which points at a curated row.
enum ShareableType: String, Sendable {
    case app
    case song
    case playlist
    case companyPlaylist
    case userPlaylist
    case creator
    case verseOfDay
    case bibleVerse
}
