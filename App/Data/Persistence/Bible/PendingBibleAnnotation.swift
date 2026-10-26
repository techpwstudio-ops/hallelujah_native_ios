import Foundation
import GRDB

/// A highlight or note saved while the server couldn't be reached, waiting
/// to be sent (`BibleRepository.flushPendingAnnotations`). One row per verse
/// and kind: a newer edit replaces the older one, since each sync sends the
/// verse's whole state (all highlighted words, or the full note text).
struct PendingBibleAnnotation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "pending_bible_annotations"

    enum Kind: String, Codable, Sendable {
        case highlight
        case note
    }

    var id: Int64?
    let kind: Kind
    let verseID: String
    let languageName: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    /// `highlight`: JSON `[VerseHighlight.Word]` (empty removes it).
    /// `note`: the UTF-8 note text (empty deletes it).
    let payload: Data
    let updatedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var location: BibleVerseLocation {
        BibleVerseLocation(
            languageName: languageName,
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            verseNumber: verseNumber
        )
    }

    var highlightWords: [VerseHighlight.Word] {
        (try? JSONDecoder().decode([VerseHighlight.Word].self, from: payload)) ?? []
    }

    var noteContent: String {
        String(decoding: payload, as: UTF8.self)
    }
}

/// The queue `PendingBibleAnnotation` rows live in.
final class PendingBibleAnnotationStore: Sendable {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func enqueue(kind: PendingBibleAnnotation.Kind, verseID: String, location: BibleVerseLocation, payload: Data) async {
        try? await database.queue.write { db in
            let existing = try PendingBibleAnnotation
                .filter(Column("kind") == kind.rawValue && Column("verseID") == verseID)
                .fetchOne(db)
            var record = PendingBibleAnnotation(
                id: existing?.id,
                kind: kind,
                verseID: verseID,
                languageName: location.languageName,
                bookNumber: location.bookNumber,
                chapterNumber: location.chapterNumber,
                verseNumber: location.verseNumber,
                payload: payload,
                updatedAt: Date()
            )
            try record.save(db)
        }
    }

    func all() async -> [PendingBibleAnnotation] {
        (try? await database.queue.read { db in
            try PendingBibleAnnotation.order(Column("updatedAt").asc).fetchAll(db)
        }) ?? []
    }

    func pending(bookNumber: Int, chapterNumber: Int) async -> [PendingBibleAnnotation] {
        (try? await database.queue.read { db in
            try PendingBibleAnnotation
                .filter(Column("bookNumber") == bookNumber && Column("chapterNumber") == chapterNumber)
                .fetchAll(db)
        }) ?? []
    }

    /// Drops the verse's queued edit. With `ifUnchangedSince`, only when no
    /// newer edit replaced it while it was being sent.
    func remove(kind: PendingBibleAnnotation.Kind, verseID: String, ifUnchangedSince date: Date? = nil) async {
        try? await database.queue.write { db in
            var request = PendingBibleAnnotation
                .filter(Column("kind") == kind.rawValue && Column("verseID") == verseID)
            if let date {
                request = request.filter(Column("updatedAt") == date)
            }
            _ = try request.deleteAll(db)
        }
    }

    func removeAll() async {
        try? await database.queue.write { db in
            _ = try PendingBibleAnnotation.deleteAll(db)
        }
    }
}
