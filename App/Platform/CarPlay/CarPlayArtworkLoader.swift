import CryptoKit
import UIKit

/// T50 — CarPlay artwork: three tiers, same as the Flutter delegate's
/// `loadImage` (in-memory → disk → network), so scrolling a list or
/// reconnecting to the head unit doesn't re-fetch what's already been seen.
///
/// - Memory + network + downsampling: `ArtworkImageCache` (shared with the
///   phone UI), which already de-duplicates in-flight requests.
/// - Disk: this type. `Caches/CarPlayArtwork/<sha256(url)>.png`, so a new
///   drive's first connect renders from disk with no network round-trip.
///   Lives in `Caches`, so the OS may purge it — a miss just falls through.
actor CarPlayArtworkLoader {
    static let shared = CarPlayArtworkLoader()

    /// Pixel size of the longest edge fetched/decoded — CarPlay list rows
    /// and rail tiles never display larger than this.
    static let maxPixelSize: CGFloat = 240

    private let directory: URL?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let directory = caches?.appendingPathComponent("CarPlayArtwork", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.directory = directory
    }

    /// `headers` carries the bearer token for artwork served through the
    /// authenticated proxy (see `NowPlayingCoordinator`'s same split); CDN
    /// URLs need none.
    func image(for url: URL?, headers: [String: String]? = nil) async -> UIImage? {
        guard let url else { return nil }

        let diskURL = diskURL(for: url)
        if let diskURL, let cached = UIImage(contentsOfFile: diskURL.path) {
            return cached
        }

        let size = Self.maxPixelSize
        guard let image = await ArtworkImageCache.shared.image(for: url, maxPixelSize: size, headers: headers) else {
            return nil
        }
        if let diskURL, let data = image.pngData() {
            try? data.write(to: diskURL, options: .atomic)
        }
        return image
    }

    private func diskURL(for url: URL) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("png")
    }

    /// Crops to a circle for artist avatars — CarPlay's own card element
    /// only offers rounded squares, so the circle is baked into the pixels.
    nonisolated static func circular(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: image.size)).addClip()
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
