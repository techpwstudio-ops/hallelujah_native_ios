import UIKit
import ImageIO

/// Fetches and downsamples artwork so the app never retains a full-resolution
/// decoded bitmap behind a thumbnail-sized view. Native equivalent of
/// `image_loader.dart`'s `ResizeImage` + `_decodeSize`, whose own comment
/// names exactly this problem: undownsampled decodes are "the main driver of
/// memory pressure / GC pauses behind the main-thread ANRs".
/// `CGImageSourceCreateThumbnailAtIndex` with
/// `kCGImageSourceThumbnailMaxPixelSize` is ImageIO's built-in equivalent of
/// Dart's decode-time resize: it downsamples *during* decode rather than
/// decoding full-size and scaling after, which is the whole point.
///
/// Dart passes `decodeWidth` *or* `decodeHeight` (never both, "so the aspect
/// ratio is preserved") — `kCGImageSourceThumbnailMaxPixelSize` already
/// bounds only the longer axis regardless of orientation, which is the same
/// one-axis intent expressed as ImageIO's own native idiom rather than a
/// direct port of Dart's width-or-height branch.
///
/// An `actor`, not `@MainActor`: decoding runs off the main thread deliberately
/// (this is the exact main-thread work Dart's comment blames for ANRs),
/// unlike this codebase's `@Observable @MainActor` view models.
actor ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200 // matches the cap AppImageCacheManager's own Dart-side doc comment calls out as the fix target — see image_loader.dart
        return cache
    }()
    private var inFlight: [String: Task<SendableImage?, Never>] = [:]

    private init() {}

    /// `headers`: needed only for a proxy-fallback artwork URL (T32's Now
    /// Playing artwork, `NowPlayingCoordinator`) — the CDN-thumbnail path
    /// this cache was originally built for never needs any, per this file's
    /// own doc comment below. `nil` (the default) matches every call site
    /// that predates T32 exactly.
    func image(for url: URL, maxPixelSize: CGFloat, headers: [String: String]? = nil) async -> UIImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return (await existing.value)?.image
        }

        let task = Task<SendableImage?, Never> {
            await Self.fetchAndDownsample(url: url, maxPixelSize: maxPixelSize, headers: headers).map(SendableImage.init)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            cache.setObject(result.image, forKey: key as NSString)
        }
        return result?.image
    }

    private func cacheKey(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize.rounded()))"
    }

    /// Direct `URLSession.shared`, not `HTTPClient`: `HTTPClient` builds
    /// JSON-API requests against `Endpoint`s resolved relative to
    /// `apiBaseURL`/`proxyBaseURL` (auth bearer token, `Content-Type:
    /// application/json`, `secure` header) — wrong shape for an
    /// unauthenticated `GET` of a fully-qualified CDN image URL. Dart draws
    /// the same line: `CachedNetworkImageProvider` never goes through
    /// `DioApi`, and `S3Service.headersFor` returns no headers at all for a
    /// direct CloudFront URL, only for the proxy-fallback path
    /// (`s3_service.dart:320-323`) — `headers` (T32) is that one exception,
    /// a plain per-request header dictionary rather than a second client.
    private static func fetchAndDownsample(url: URL, maxPixelSize: CGFloat, headers: [String: String]?) async -> UIImage? {
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// `UIImage` isn't declared `Sendable` in the SDK this was written against,
/// even though Apple documents it as safe to read from any thread once
/// created (immutable after init from a `CGImage`) — this box carries a
/// decoded thumbnail across the `Task` boundary above without losing that
/// (accurate) safety property to an unconfirmed compiler gap. Flag alongside
/// `GlassSurface`'s own unconfirmed-API note if a real build disagrees.
private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}
