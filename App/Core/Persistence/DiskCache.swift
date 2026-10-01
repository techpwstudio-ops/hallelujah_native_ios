import CryptoKit
import Foundation

/// File-based cache under Library/Caches (purgeable by the OS under storage
/// pressure) — for artwork and other re-fetchable remote assets. Never for
/// data that must survive without a network round-trip; downloads get their
/// own storage (T46), not this.
///
/// Eviction: `trim(toByteLimit:)` deletes the least-recently-accessed files
/// first until the cache is back under the limit. Nothing calls this
/// automatically yet — T13 (media components) wires it into the artwork
/// pipeline once that exists.
final class DiskCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directoryName: String) throws {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Touch the modification date so trim()'s LRU ordering reflects reads, not just writes.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func setData(_ data: Data, forKey key: String) throws {
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    func removeData(forKey key: String) {
        try? fileManager.removeItem(at: fileURL(forKey: key))
    }

    /// Deletes least-recently-accessed files first until total size is under `byteLimit`.
    func trim(toByteLimit byteLimit: Int) {
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: resourceKeys
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, size)
        }.sorted { $0.date < $1.date }

        var totalSize = entries.reduce(0) { $0 + $1.size }
        for entry in entries {
            guard totalSize > byteLimit else { break }
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }

    /// SHA256, not `String.hashValue` — Swift's hash seed is randomized per
    /// process, so the same key would map to a different filename on every
    /// launch and nothing would ever be found in the cache.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename)
    }
}
