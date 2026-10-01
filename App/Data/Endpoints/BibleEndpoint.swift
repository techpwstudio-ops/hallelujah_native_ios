import Foundation

extension Endpoint {
    // MARK: Bible / Reader (T54) — `src/routes/user/book.routes.js` +
    // `book.controller.js`, all mounted behind `authMiddleware`.

    /// `GET /book/init` — books + language list.
    static var bibleInit: Endpoint {
        .get("/book/init")
    }

    /// `GET /book/chapter/verses?bookNumber&chapterNumber&languageName&
    /// isBookNumberChanged&isChapterNumberChanged`. The last two are
    /// optional booleans sent as the literal string `"true"`/`"false"` —
    /// the server only includes `notes`/`highlights` in the response when
    /// at least one is exactly `"true"`.
    static func bibleChapterVerses(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool
    ) -> Endpoint {
        .get(
            "/book/chapter/verses?bookNumber=\(bookNumber)&chapterNumber=\(chapterNumber)" +
                "&languageName=\(languageName)&isBookNumberChanged=\(isBookNumberChanged)" +
                "&isChapterNumberChanged=\(isChapterNumberChanged)"
        )
    }

    /// `POST /book/verse/highlight/sync`.
    static var bibleHighlightSync: Endpoint {
        .post("/book/verse/highlight/sync")
    }

    /// `POST /book/verse/notes/sync`.
    static var bibleNoteSync: Endpoint {
        .post("/book/verse/notes/sync")
    }

    /// `GET /book/verse/share/:id` — `id` is a `BibleVerse.id`.
    static func bibleVerseShare(id: String) -> Endpoint {
        .get("/book/verse/share/" + id)
    }

    // MARK: Offline bible and search (T55) — same route file, `searchBible`/
    // `triggerBookSnapshot` in `book.controller.js`.

    /// `GET /book/search?q&languageName&limit`. `limit` is 1-50, server
    /// default 20 when omitted — always sent here regardless, matching
    /// Dart's own `BibleSearchService.search` default argument.
    static func bookSearch(query: String, languageName: String, limit: Int) -> Endpoint {
        .get(
            "/book/search?q=\(percentEncodedQuery(query))" +
                "&languageName=\(percentEncodedQuery(languageName))&limit=\(limit)"
        )
    }

    /// `POST /book/snapshot/trigger`, body `{languageName}`.
    static var bibleSnapshotTrigger: Endpoint {
        .post("/book/snapshot/trigger")
    }

    /// Same allowed-character policy as `Endpoint.search`'s own
    /// `percentEncoded` (T40) — free text (`q`) can contain `&`/`=`/`+`/
    /// spaces/`:` (book references like "John 3:16"), none of which are
    /// safe to paste directly into a hand-built query string.
    private static func percentEncodedQuery(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}
