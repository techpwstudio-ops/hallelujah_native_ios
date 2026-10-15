import Foundation
import GRDB

/// The on-device mirror of Dart's Realm-backed "instant on cached books" /
/// notes-ledger behavior (see `RemoteBibleRepository`'s doc comments for
/// how each method is used).
protocol BibleChapterCaching: Sendable {
    func chapter(languageName: String, bookNumber: Int, chapterNumber: Int) async -> BibleChapter?
    func store(_ chapter: BibleChapter) async
    func upsertLocalNote(_ note: VerseNote, bookNumber: Int, chapterNumber: Int, verseNumber: Int) async
    func deleteLocalNote(verseID: String) async
    func allLocalNotes() async -> [BibleNoteEntry]

    /// T55 — drops every cached chapter of one language, e.g. "remove
    /// offline Bible" long-press. Leaves notes/highlights alone: those are
    /// per-user server-synced data (`upsertLocalNote`), not part of the
    /// offline snapshot this clears.
    func deleteChapters(languageName: String) async
}

final class BibleChapterCache: BibleChapterCaching, Sendable {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func chapter(languageName: String, bookNumber: Int, chapterNumber: Int) async -> BibleChapter? {
        let key = Self.cacheKey(languageName: languageName, bookNumber: bookNumber, chapterNumber: chapterNumber)
        guard let record = try? await database.queue.read({ db in
            try CachedBibleChapter.filter(Column("cacheKey") == key).fetchOne(db)
        }) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard
            let verses = try? decoder.decode([BibleVerse].self, from: record.versesData),
            let notes = try? decoder.decode([VerseNote].self, from: record.notesData),
            let highlights = try? decoder.decode([VerseHighlight].self, from: record.highlightsData)
        else {
            return nil
        }
        return BibleChapter(
            bookNumber: record.bookNumber,
            chapterNumber: record.chapterNumber,
            languageName: record.languageName,
            verses: verses,
            notes: notes,
            highlights: highlights
        )
    }

    func store(_ chapter: BibleChapter) async {
        let key = Self.cacheKey(
            languageName: chapter.languageName,
            bookNumber: chapter.bookNumber,
            chapterNumber: chapter.chapterNumber
        )
        let encoder = JSONEncoder()
        guard
            let versesData = try? encoder.encode(chapter.verses),
            let notesData = try? encoder.encode(chapter.notes),
            let highlightsData = try? encoder.encode(chapter.highlights)
        else {
            return
        }
        try? await database.queue.write { db in
            var record = try CachedBibleChapter.filter(Column("cacheKey") == key).fetchOne(db) ?? CachedBibleChapter(
                id: nil,
                cacheKey: key,
                languageName: chapter.languageName,
                bookNumber: chapter.bookNumber,
                chapterNumber: chapter.chapterNumber,
                versesData: versesData,
                notesData: notesData,
                highlightsData: highlightsData,
                cachedAt: Date()
            )
            record = CachedBibleChapter(
                id: record.id,
                cacheKey: key,
                languageName: chapter.languageName,
                bookNumber: chapter.bookNumber,
                chapterNumber: chapter.chapterNumber,
                versesData: versesData,
                notesData: notesData,
                highlightsData: highlightsData,
                cachedAt: Date()
            )
            try record.save(db)
        }
    }

    func upsertLocalNote(_ note: VerseNote, bookNumber: Int, chapterNumber: Int, verseNumber: Int) async {
        try? await database.queue.write { db in
            let existing = try CachedVerseNote.filter(Column("verseID") == note.verseId).fetchOne(db)
            var record = CachedVerseNote(
                id: existing?.id,
                verseID: note.verseId,
                bookNumber: bookNumber,
                chapterNumber: chapterNumber,
                verseNumber: verseNumber,
                content: note.content,
                // The Notes list shows/sorts by the note's server `createdAt`
                // (Flutter `SORT(createdAt desc)`); a re-fetch of the chapter
                // must not reset it to "now".
                updatedAt: Self.parseServerDate(note.createdAt) ?? existing?.updatedAt ?? Date()
            )
            try record.save(db)
        }
    }

    private static func parseServerDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    func deleteLocalNote(verseID: String) async {
        try? await database.queue.write { db in
            _ = try CachedVerseNote.filter(Column("verseID") == verseID).deleteAll(db)
        }
    }

    func allLocalNotes() async -> [BibleNoteEntry] {
        let records = (try? await database.queue.read { db in
            try CachedVerseNote.order(Column("updatedAt").desc).fetchAll(db)
        }) ?? []
        let decoder = JSONDecoder()
        var entries: [BibleNoteEntry] = []
        for note in records {
            // The note row stores no verse text; borrow it (and the language)
            // from whichever cached chapter holds this verse.
            let chapters = (try? await database.queue.read { db in
                try CachedBibleChapter
                    .filter(Column("bookNumber") == note.bookNumber && Column("chapterNumber") == note.chapterNumber)
                    .fetchAll(db)
            }) ?? []
            var verseText: String?
            var languageName: String?
            for chapter in chapters {
                guard let verses = try? decoder.decode([BibleVerse].self, from: chapter.versesData),
                      let verse = verses.first(where: { $0.id == note.verseID }) else { continue }
                verseText = verse.text
                languageName = chapter.languageName
                break
            }
            entries.append(BibleNoteEntry(
                verseID: note.verseID,
                bookNumber: note.bookNumber,
                chapterNumber: note.chapterNumber,
                verseNumber: note.verseNumber,
                content: note.content,
                updatedAt: note.updatedAt,
                verseText: verseText,
                languageName: languageName
            ))
        }
        return entries
    }

    func deleteChapters(languageName: String) async {
        try? await database.queue.write { db in
            _ = try CachedBibleChapter.filter(Column("languageName") == languageName).deleteAll(db)
        }
    }

    private static func cacheKey(languageName: String, bookNumber: Int, chapterNumber: Int) -> String {
        "\(languageName)|\(bookNumber)|\(chapterNumber)"
    }
}
