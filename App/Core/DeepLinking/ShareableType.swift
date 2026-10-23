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
    /// A shared Emet answer (`/ai/messages/:id/share`). Not in Flutter's
    /// enum; the recipient lands on the Emet tab.
    case aiMessage

    /// The server's type name, with the spellings an Emet share may carry
    /// mapped onto `aiMessage` (the exact name isn't pinned in the client).
    init?(serverValue: String) {
        if let known = ShareableType(rawValue: serverValue) {
            self = known
            return
        }
        switch serverValue.lowercased() {
        case "aimessage", "ai_message", "ai", "aichat", "aiconversation", "emet":
            self = .aiMessage
        default:
            return nil
        }
    }
}
