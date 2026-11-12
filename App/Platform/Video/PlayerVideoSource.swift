import Foundation

/// Where an episode's silent video comes from and how it is asked for: the same authenticated media
/// proxy as the audio, with the same headers.
///
/// The audio side builds its own resolver and spells its own headers out; this is the video's
/// counterpart for the views, so no view needs the proxy's address or a token provider.
struct PlayerVideoSource: Sendable {
    private let resolver: AudioSourceResolver
    private let tokenProvider: any AuthTokenProviding

    init(proxyBaseURL: URL, tokenProvider: any AuthTokenProviding) {
        resolver = AudioSourceResolver(proxyBaseURL: proxyBaseURL)
        self.tokenProvider = tokenProvider
    }

    /// The song's video, `nil` when it has none (no key, or a blank one). A key that is there but
    /// cannot be turned into a URL is also `nil`; the caller tells the two apart with `Song.hasVideo`.
    func url(for song: Song) -> URL? {
        url(for: song, choice: nil)
    }

    /// The song's video at the chosen quality. A choice with a file name plays that rendition, beside
    /// `videoFile`; no choice, or one without a file name (the original), plays `videoFile` itself.
    func url(for song: Song, choice: VideoQualityChoice?) -> URL? {
        guard let key = song.videoFile else { return nil }
        if let fileName = choice?.variantFileName {
            return resolver.videoURL(forKey: key, variantFileName: fileName)
        }
        return resolver.videoURL(forKey: key)
    }

    /// The request headers for the proxy. The token is fetched, and refreshed first if it has
    /// expired, at the moment the video opens, so a reopened player never carries a stale one.
    func headers() async -> [String: String] {
        ProxyRequestHeaders.make(token: await tokenProvider.validAccessToken())
    }
}
