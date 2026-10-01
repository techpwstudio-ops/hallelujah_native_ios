import Foundation
import GRDB

/// GRDB for structured data (bible/library tables — Q2 in progress.md; plain
/// files handle downloads instead, see `DiskCache` and T46).
///
/// A single `DatabaseQueue`, not a pool: GRDB serializes writes internally
/// regardless, and a queue is the simpler default until profiling says a
/// pool's concurrent reads are actually needed.
final class Database: Sendable {
    let queue: DatabaseQueue

    init(path: URL, migrator: DatabaseMigrator) throws {
        queue = try DatabaseQueue(path: path.path)
        try migrator.migrate(queue)
    }

    static func makeDefault(migrator: DatabaseMigrator = .empty) throws -> Database {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try Database(path: directory.appendingPathComponent("ghallelujah.sqlite"), migrator: migrator)
    }
}

extension DatabaseMigrator {
    /// No migrations registered yet. Each feature task (T27+) adds its own
    /// `registerMigration("...")` here, in order, as it defines tables —
    /// nothing pre-declared for schemas that don't exist yet.
    static var empty: DatabaseMigrator {
        DatabaseMigrator()
    }
}
