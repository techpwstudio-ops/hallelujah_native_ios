import Foundation

/// Plain-file store for the download catalog: a `Downloads` subdirectory
/// under Application Support — the same base directory `Database.swift`
/// already uses, deliberately not `Library/Caches` (`DiskCache`'s own doc
/// comment: "Never for data that must survive without a network
/// round-trip; downloads get their own storage (T46), not this" — the OS is
/// free to purge `Caches` under storage pressure, but never Application
/// Support). The subdirectory holds the downloaded audio files themselves,
/// named by `DownloadTask.localFileName`, plus one `catalog.json` file
/// holding the full task array, rewritten atomically on every save. GRDB has
/// no table for this (`Database.swift`'s own doc comment: zero tables
/// registered, plain files handle downloads instead); this is that plain
/// file.
///
/// Follows `DiskCache`'s own `FileManager` conventions closely — same
/// directory-creation shape, just a different base directory and one added
/// JSON read/write for the catalog itself.
final class DownloadCatalogStore: @unchecked Sendable {
    /// The `Downloads` subdirectory holding the audio files themselves,
    /// named by `DownloadTask.localFileName`. Exposed so `DownloadEngine`
    /// can build full file URLs for a completed download and pick a
    /// destination URL for a new one before its task starts.
    let downloadsDirectory: URL

    private let catalogURL: URL
    private let fileManager = FileManager.default

    init() throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        downloadsDirectory = directory
        catalogURL = directory.appendingPathComponent("catalog.json")
    }

    /// Empty when nothing has been saved yet, or the catalog file is
    /// missing/corrupt — same "absent cache reads as empty" posture
    /// `HomeFeedCache.load` and `RecentSearchStore.init` already take.
    func load() -> [DownloadTask] {
        guard let data = try? Data(contentsOf: catalogURL),
              let tasks = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            return []
        }
        return tasks
    }

    /// Rewrites the whole catalog. `DownloadEngine` calls this with its
    /// full in-memory task list after every mutating operation, so the file
    /// is always the unit of persistence — no row-level writes to keep in
    /// sync.
    func save(_ tasks: [DownloadTask]) throws {
        let data = try JSONEncoder().encode(tasks)
        try data.write(to: catalogURL, options: .atomic)
    }
}
