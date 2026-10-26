import CryptoKit
import Foundation

/// Every artwork image the app fetches, kept on disk automatically — the
/// native counterpart of Flutter's `AppImageCacheManager`
/// (`cached_network_image` with 30-day / 2000-object limits). Unlike the
/// `URLCache` in front of the network, which honours server cache headers
/// and drops large items, this always keeps the bytes, so anything seen
/// once loads again with no connection. Lives in Caches: the OS may purge
/// it under storage pressure; downloaded songs' artwork is kept separately
/// and permanently by `OfflineArtworkStore`.
enum ArtworkDiskCache {
    /// Flutter's `stalePeriod`.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    static let maxBytes: Int64 = 200 * 1024 * 1024

    private static let lock = NSLock()
    nonisolated(unsafe) private static var writesSinceTrim = 0

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("ArtworkCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileURL(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return directory?.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    /// `nil` when missing or older than `maxAge`.
    static func data(for url: URL) -> Data? {
        guard let file = fileURL(for: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge
        else { return nil }
        return try? Data(contentsOf: file)
    }

    static func save(_ data: Data, for url: URL) {
        guard let file = fileURL(for: url) else { return }
        try? data.write(to: file, options: .atomic)
        lock.lock()
        writesSinceTrim += 1
        let shouldTrim = writesSinceTrim >= 100
        if shouldTrim { writesSinceTrim = 0 }
        lock.unlock()
        if shouldTrim { trim() }
    }

    /// Drops expired files, then the oldest until under `maxBytes`.
    static func trim() {
        guard let directory else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = files.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        let now = Date()
        entries.removeAll { entry in
            guard now.timeIntervalSince(entry.date) >= maxAge else { return false }
            try? FileManager.default.removeItem(at: entry.url)
            return true
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > maxBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Sign-out.
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
