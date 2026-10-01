import Foundation
import GRDB

final class AnalyticsEventStore: Sendable {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func enqueue(_ event: any AnalyticsEvent) throws {
        let payload = try JSONEncoder().encode(event)
        var record = QueuedAnalyticsEvent(id: nil, eventName: event.eventName, payload: payload, enqueuedAt: Date())
        try database.queue.write { db in
            try record.insert(db)
        }
    }

    func oldestBatch(limit: Int) throws -> [QueuedAnalyticsEvent] {
        try database.queue.read { db in
            try QueuedAnalyticsEvent
                .order(Column("enqueuedAt"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func delete(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try database.queue.write { db in
            _ = try QueuedAnalyticsEvent.deleteAll(db, keys: ids)
        }
    }
}
