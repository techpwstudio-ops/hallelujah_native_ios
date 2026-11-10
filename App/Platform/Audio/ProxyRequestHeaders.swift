import Foundation

/// The headers an `AVPlayer` sends to the media proxy (`GET /api/proxy?path=<key>`), in one place.
///
/// The same proxy and the same auth middleware serve the audio and the silent video, so both send
/// the same pair. `AudioEngine.makePlayerItem` still spells these two out inline: it is left alone
/// by the silent video feature, and a later change can adopt this helper there.
enum ProxyRequestHeaders {
    /// `token` comes from `AuthTokenProviding.validAccessToken()`, which refreshes an expired token
    /// first. A missing token is sent as an empty bearer, as the engine does: the proxy answers 401
    /// and the player reports a failure, which is the honest outcome.
    static func make(token: String?) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token ?? "")",
        ]
    }
}
