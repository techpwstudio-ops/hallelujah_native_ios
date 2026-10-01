import Foundation

/// Resolves a raw storage `path` (as stored on a song/creator/playlist model)
/// to a fully-qualified image URL. Mirrors `S3Service.getFileUrl`'s image
/// thumbnail branch (`lib/services/s3_service.dart:65-126`) exactly: same
/// `/thumbnail-`/`/thumbnails` path-pattern check, same `allowedVariants`
/// substring test (a plain `contains`, not a split/tokenized list — that's
/// only how the sibling audio-variant branch works, which this resolver does
/// not implement), same system-avatar bypass, same `<variant>.webp` filename
/// rewrite, same `proxy?path=` fallback for anything else. Audio-variant
/// selection is out of scope here.
///
/// Lives under `App/Data/Media/`, not `DesignSystem/Components/Media/`:
/// `ArtworkView` (the DesignSystem side) takes an already-resolved `URL?`
/// and has no dependency on `AppConfiguration` — this is the one piece that
/// does (per D2's layering), the same way `S3Service` itself lives in Dart's
/// services layer rather than inside a widget. No `Media/` folder was
/// pre-scaffolded under `App/Data` the way `Components/Media` was under
/// DesignSystem (see T12's Status log) — added here to keep the two layers'
/// folder names symmetric with the DesignSystem side.
///
/// `cdnHost` is derived from `RemoteSettings.current.cdnUrl` (T15), falling
/// back to `AppConfiguration`'s compile-time xcconfig value only if that URL
/// somehow fails to parse a host. This now matches Dart's own
/// `EndPoints.cloudFrontUrl` -> `SettingsService.instance.cdnUrl` indirection
/// (`lib/utils/end_points.dart`) — see `RemoteSettings`'s doc comment for why
/// that value is a launch-time default rather than a live fetch today, same
/// as it effectively is in Dart on a cold start.
struct ArtworkURLResolver: Sendable {
    private let cdnHost: String
    private let proxyBaseURL: URL

    init(configuration: AppConfiguration = .current) {
        self.cdnHost = URL(string: RemoteSettings.current.cdnUrl)?.host ?? configuration.cdnHost
        self.proxyBaseURL = configuration.proxyBaseURL
    }

    /// - Parameters:
    ///   - path: Raw storage path from the model, e.g. the path backing
    ///     `Song.imageVariants` (`lib/models/song.dart`).
    ///   - variant: The size to request.
    ///   - allowedVariants: The comma-ish string of variants the backend
    ///     says this asset actually has, from the same model field Dart
    ///     passes to `getFileUrl(allowedVariants:)`. `nil`, or not
    ///     containing `variant`, falls back to the untransformed thumbnail
    ///     path — exactly what the Dart branch does.
    func resolve(path: String?, variant: ImageVariant, allowedVariants: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }

        if path.contains("/thumbnail-") || path.contains("/thumbnails") {
            if let allowedVariants, allowedVariants.contains(variant.rawValue), !isSystemImage(path) {
                let rewritten = rewritingFileName(in: path, to: "\(variant.rawValue).webp")
                return URL(string: "https://\(cdnHost)/\(rewritten)")
            }
            return URL(string: "https://\(cdnHost)/\(path)")
        }

        if path.hasPrefix("https://") {
            return URL(string: path)
        }

        return proxyURL(path: path)
    }

    private func isSystemImage(_ path: String) -> Bool {
        path.contains("hallelujah/system/public/avatars")
    }

    /// Replaces only the last path component, matching Dart's
    /// `path.replaceFirst(fileName, '$variant.webp')` where `fileName` is
    /// `path.split('/').last` — implemented as a slice-and-append instead of
    /// a string search-and-replace so a filename that happens to recur
    /// earlier in the path is never touched, which is what "replace the
    /// filename" actually means here.
    private func rewritingFileName(in path: String, to newFileName: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return newFileName }
        return String(path[path.startIndex...lastSlash]) + newFileName
    }

    /// `$s3BucketUrl$path` in Dart, where `s3BucketUrl` is itself
    /// `'${EndPoints.proxyUrl}/proxy?path='` (`s3_service.dart:326`) — not a
    /// literal string concatenation here, so `path` (which may contain `/`
    /// and other reserved characters) gets properly percent-encoded as a
    /// query value instead of pasted in raw.
    private func proxyURL(path: String) -> URL? {
        guard var components = URLComponents(
            url: proxyBaseURL.appendingPathComponent("proxy"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}
