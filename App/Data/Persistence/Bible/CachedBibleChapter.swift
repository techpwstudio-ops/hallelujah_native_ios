import Foundation
import GRDB

/// A cached chapter's last-known verses/notes/highlights — lets a cache hit
/// return the full chapter (not just verse text) instantly, mirroring
/// Dart's Realm-backed "instant on cached books" behavior. Keyed on
/// `cacheKey` (`languageName + "|" + bookNumber + "|" + chapterNumber`)
/// rather than a compound primary key, matching `QueuedAnalyticsEvent`'s
/// single-autoincrement-id-plus-unique-column shape.
struct CachedBibleChapter: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "cached_bible_chapters"

    var id: Int64?
    let cacheKey: String
    let languageName: String
    let bookNumber: Int
    let chapterNumber: Int
    let versesData: Data
    let notesData: Data
    let highlightsData: Data
    let cachedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The local "My Notes" ledger row (`BibleRepository.fetchLocalNotes`) —
/// accumulated as chapters are read / notes are saved, since the backend
/// has no bulk notes-listing endpoint.
struct CachedVerseNote: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "cached_verse_notes"

    var id: Int64?
    let verseID: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    let content: String
    let updatedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension DatabaseMigrator {
    /// Added alongside the existing `registerAnalyticsMigrations()` call,
    /// not a replacement — wired in `AppComposition.swift` by a deferred
    /// patch, not called from here.
    mutating func registerBibleMigrations() {
        registerMigration("createCachedBibleChapters") { db in
            try db.create(table: CachedBibleChapter.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("cacheKey", .text).notNull().unique()
                table.column("languageName", .text).notNull()
                table.column("bookNumber", .integer).notNull()
                table.column("chapterNumber", .integer).notNull()
                table.column("versesData", .blob).notNull()
                table.column("notesData", .blob).notNull()
                table.column("highlightsData", .blob).notNull()
                table.column("cachedAt", .datetime).notNull()
            }
        }
        registerMigration("createCachedVerseNotes") { db in
            try db.create(table: CachedVerseNote.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("verseID", .text).notNull().unique()
                table.column("bookNumber", .integer).notNull()
                table.column("chapterNumber", .integer).notNull()
                table.column("verseNumber", .integer).notNull()
                table.column("content", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        registerMigration("createPendingBibleAnnotations") { db in
            try db.create(table: PendingBibleAnnotation.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("kind", .text).notNull()
                table.column("verseID", .text).notNull()
                table.column("languageName", .text).notNull()
                table.column("bookNumber", .integer).notNull()
                table.column("chapterNumber", .integer).notNull()
                table.column("verseNumber", .integer).notNull()
                table.column("payload", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.uniqueKey(["kind", "verseID"])
            }
        }
    }
}
