import Foundation

/// Resolves a `Song` to a playable URL at the best available quality.
/// Ports `S3Service`'s two-tier resolution (`s3_service.dart`):
///
/// 1. A still-valid pre-signed CloudFront URL from `song.audioUrls` — cheap,
///    no backend load, but expires ~3h after issue.
/// 2. The authenticated proxy, at the same quality cap, if that variant
///    exists on S3 at all (independent of whether a presigned URL for it is
///    currently valid).
///
/// Dart only ever reaches tier 2 reactively, after a play failure
/// (`_setPlayerSourcesWithRetry` just retries the identical dead URL twice
/// first) — a gap its own author flagged. This resolves tier 2 proactively
/// the first time tier 1 doesn't check out, and `AudioEngine` also calls
/// `resolveViaProxy` directly on an item playback failure.
struct AudioSourceResolver: Sendable {
    struct ResolvedSource: Sendable, Equatable {
        let url: URL
        let quality: AudioQuality
        let requiresAuthHeader: Bool
    }

    private let proxyBaseURL: URL

    init(proxyBaseURL: URL) {
        self.proxyBaseURL = proxyBaseURL
    }

    /// `nil` only when the song has no audio at all (no valid presigned URL
    /// of any kind and no `audioFile` to proxy) — callers should treat that
    /// as a genuine playback error, not retry.
    func resolve(song: Song, targetQuality: AudioQuality) -> ResolvedSource? {
        resolveCloudFront(song: song, targetQuality: targetQuality)
            ?? resolveViaProxy(song: song, targetQuality: targetQuality)
    }

    // MARK: - Tier 1: pre-signed CloudFront

    /// `resolveValidPresignedAudioUrlForQuality` (s3_service.dart:222-251):
    /// graceful degrade within the requested quality (high -> standard ->
    /// low; standard -> low; low only), each candidate gated on its own URL
    /// not being within 5 minutes of `Expires`. Falls to `.original` only
    /// when no optimized variant is available at all — the only case
    /// `SongAudioURLs.original` is ever populated (see its own doc comment).
    private func resolveCloudFront(song: Song, targetQuality: AudioQuality) -> ResolvedSource? {
        let candidates: [(AudioQuality, URL?)] = switch targetQuality {
        case .high: [(.high, song.audioUrls.high), (.standard, song.audioUrls.standard), (.low, song.audioUrls.low)]
        case .standard: [(.standard, song.audioUrls.standard), (.low, song.audioUrls.low)]
        case .low: [(.low, song.audioUrls.low)]
        }
        for (quality, url) in candidates {
            if let url, Self.isPresignedURLValid(url) {
                return ResolvedSource(url: url, quality: quality, requiresAuthHeader: false)
            }
        }
        if let original = song.audioUrls.original, Self.isPresignedURLValid(original) {
            return ResolvedSource(url: original, quality: targetQuality, requiresAuthHeader: false)
        }
        return nil
    }

    /// `isPresignedUrlValid` (s3_service.dart:202-213): parses CloudFront's
    /// `Expires` query param (Unix seconds); valid only if it's still more
    /// than 5 minutes away.
    private static func isPresignedURLValid(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expiresValue = components.queryItems?.first(where: { $0.name == "Expires" })?.value,
              let expires = TimeInterval(expiresValue)
        else { return false }
        return expires > Date().timeIntervalSince1970 + 300
    }

    // MARK: - Tier 2: authenticated proxy

    /// `getFileUrlForQuality` (s3_service.dart:265-291): swaps the filename
    /// in `audioFile`'s S3 key for the resolved variant's own filename (e.g.
    /// `songs/abc/original.m4a` -> `songs/abc/high.m4a`), still capped at
    /// `targetQuality`. Needs `audioVariants`'s raw wire string here (unlike
    /// tier 1, which only needs `audioUrls`) because the proxy derives the
    /// key itself rather than using a pre-issued URL. That string is
    /// `"low.m4a,standard.m4a,high.m4a"`-shaped — confirmed against the
    /// backend's own `audioOptimizer.job.js:186-190` comment ("existingVariants
    /// ... derived by stripping the file extension from the stored
    /// low.m4a,... string"); `SONG_RESPONSE_SHAPE.md`'s extension-less
    /// `"low,standard,high"` example is stale.
    func resolveViaProxy(song: Song, targetQuality: AudioQuality) -> ResolvedSource? {
        guard let audioFile = song.audioFile, !audioFile.isEmpty else { return nil }

        if let variant = Self.bestVariantToken(audioVariants: song.audioVariants, targetQuality: targetQuality) {
            let key = Self.replacingFileName(in: audioFile, with: variant.fileName)
            guard let url = Self.proxyURL(for: key, base: proxyBaseURL) else { return nil }
            return ResolvedSource(url: url, quality: variant.quality, requiresAuthHeader: true)
        }

        // No optimized variants at all (not yet processed) — proxy the
        // original file untouched, same "proxy if audioUrls is null
        // entirely" fallback `SONG_RESPONSE_SHAPE.md`'s Audio URL Rules call
        // for, just reached via the proxy rather than a presigned original.
        guard let url = Self.proxyURL(for: audioFile, base: proxyBaseURL) else { return nil }
        return ResolvedSource(url: url, quality: targetQuality, requiresAuthHeader: true)
    }

    /// `selectBestVariant` (s3_service.dart:148-176): among tokens at or
    /// below `targetQuality`'s rank, the highest-quality one wins.
    private static func bestVariantToken(
        audioVariants: String?,
        targetQuality: AudioQuality
    ) -> (quality: AudioQuality, fileName: String)? {
        guard let audioVariants, audioVariants.contains(".") else { return nil }
        let tokens = audioVariants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let ranked: [(AudioQuality, String)] = tokens.compactMap { token in
            guard let name = token.split(separator: ".").first,
                  let quality = AudioQuality(rawValue: String(name))
            else { return nil }
            return (quality, token)
        }
        return ranked
            .filter { $0.0 <= targetQuality }
            .max { $0.0 < $1.0 }
            .map { (quality: $0.0, fileName: $0.1) }
    }

    private static func replacingFileName(in key: String, with fileName: String) -> String {
        guard let lastSlash = key.lastIndex(of: "/") else { return fileName }
        return String(key[..<key.index(after: lastSlash)]) + fileName
    }

    /// `s3BucketUrl` (s3_service.dart:326): `{proxyBase}/proxy?path={key}`.
    /// Plain string concatenation for the base, same as `HTTPClient
    /// .makeRequest`'s own doc comment explains — `URL(string:relativeTo:)`
    /// would drop `proxyBaseURL`'s own path component instead of appending.
    private static func proxyURL(for key: String, base: URL) -> URL? {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+")
        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else { return nil }
        return URL(string: base.absoluteString + "/proxy?path=\(encodedKey)")
    }
}
