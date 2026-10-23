import CryptoKit
import Foundation

/// Artwork bytes kept on disk for downloaded songs, so the Downloads list
/// still has thumbnails offline (Flutter's `AppImageCacheManager` keeps them
/// for 30 days; `ArtworkImageCache`'s `URLCache` is best-effort, lives in
/// Caches, and only ever held the exact URLs that happened to be viewed).
/// Keyed by the artwork URL, so `ArtworkImageCache` can fall back to it for
/// any view showing that image.
enum OfflineArtworkStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("OfflineArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileURL(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name)
    }

    static func contains(_ url: URL) -> Bool {
        guard let file = fileURL(for: url) else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func data(for url: URL) -> Data? {
        guard let file = fileURL(for: url) else { return nil }
        return try? Data(contentsOf: file)
    }

    static func save(_ data: Data, for url: URL) {
        guard let file = fileURL(for: url) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Sign-out / "delete all downloads".
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
