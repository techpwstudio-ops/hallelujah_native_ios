import Foundation
import GRDB

/// The on-device mirror of Flutter's Realm-persisted `VerseOfDay` — the
/// Home card's only read (`VerseOfDayRepository.cachedVerse(id:)`), never a
/// live network fetch. Whole `VerseOfDay` stored as one JSON blob per row
/// (mirroring `CachedBibleChapter`'s `versesData` blob), keyed by its own
/// server id rather than exploded into ~15 scalar columns.
protocol VerseOfDayCaching: Sendable {
    func verse(id: String) async -> VerseOfDay?
    func store(_ verse: VerseOfDay) async
}

final class VerseOfDayCache: VerseOfDayCaching, Sendable {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func verse(id: String) async -> VerseOfDay? {
        guard let record = try? await database.queue.read({ db in
            try CachedVerseOfDay.filter(Column("verseID") == id).fetchOne(db)
        }) else {
            return nil
        }
        return try? JSONDecoder().decode(VerseOfDay.self, from: record.payload)
    }

    func store(_ verse: VerseOfDay) async {
        guard let payload = try? JSONEncoder().encode(verse) else { return }
        try? await database.queue.write { db in
            var record = try CachedVerseOfDay.filter(Column("verseID") == verse.id).fetchOne(db) ?? CachedVerseOfDay(
                id: nil,
                verseID: verse.id,
                payload: payload,
                cachedAt: Date()
            )
            record = CachedVerseOfDay(id: record.id, verseID: verse.id, payload: payload, cachedAt: Date())
            try record.save(db)
        }
    }
}

struct CachedVerseOfDay: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "cached_verse_of_days"

    var id: Int64?
    let verseID: String
    let payload: Data
    let cachedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension DatabaseMigrator {
    /// Added alongside `registerBibleMigrations()` — wired in
    /// `AppComposition.swift` by a deferred patch, not called from here.
    mutating func registerVerseOfDayMigrations() {
        registerMigration("createCachedVerseOfDays") { db in
            try db.create(table: CachedVerseOfDay.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("verseID", .text).notNull().unique()
                table.column("payload", .blob).notNull()
                table.column("cachedAt", .datetime).notNull()
            }
        }
    }
}
