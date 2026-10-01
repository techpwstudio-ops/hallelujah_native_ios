import Foundation
import GRDB

/// A locally-queued, not-yet-synced event. `payload` is the JSON encoding of
/// whatever concrete `AnalyticsEvent` was tracked — this table doesn't know
/// or care about specific event shapes.
struct QueuedAnalyticsEvent: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "queued_analytics_events"

    var id: Int64?
    let eventName: String
    let payload: Data
    let enqueuedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension DatabaseMigrator {
    mutating func registerAnalyticsMigrations() {
        registerMigration("createQueuedAnalyticsEvents") { db in
            try db.create(table: QueuedAnalyticsEvent.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("eventName", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("enqueuedAt", .datetime).notNull()
            }
        }
    }
}
