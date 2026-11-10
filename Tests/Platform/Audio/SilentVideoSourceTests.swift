import Foundation
import Testing
@testable import Hallelujah

/// `AudioSourceResolver.videoURL(forKey:)` and `ProxyRequestHeaders`: the silent video travels
/// the same proxy, encoded the same way, with the same headers as the audio.
struct SilentVideoSourceTests {
    private let resolver = AudioSourceResolver(proxyBaseURL: URL(string: "https://api.example.com/api")!)

    @Test func aPlainKeyGoesThroughTheProxy() {
        let url = resolver.videoURL(forKey: "ep/video-song/1-silent/original.mp4")
        #expect(url?.absoluteString == "https://api.example.com/api/proxy?path=ep/video-song/1-silent/original.mp4")
    }

    @Test func aBlankKeyHasNoURL() {
        #expect(resolver.videoURL(forKey: "") == nil)
        #expect(resolver.videoURL(forKey: "  \n\t ") == nil)
    }

    @Test func surroundingWhitespaceIsDropped() {
        #expect(resolver.videoURL(forKey: "  a/b.mp4 \n") == resolver.videoURL(forKey: "a/b.mp4"))
    }

    @Test func queryDelimitersInTheKeyAreEncodedLikeAudio() throws {
        // `&`, `=` and `+` would otherwise end or split the `path` value; a space and a non-ASCII
        // letter are percent-encoded by the same rule the audio path uses.
        let key = "a&b=c+d e/é.mp4"
        let url = try #require(resolver.videoURL(forKey: key))
        #expect(url.absoluteString == "https://api.example.com/api/proxy?path=a%26b%3Dc%2Bd%20e/%C3%A9.mp4")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "path")
        #expect(components.queryItems?.first?.value == "a&b=c+d e/é.mp4")
    }

    @Test func theVideoURLMatchesTheAudioProxyURLForTheSameKey() throws {
        let song = Song.fixture(audioFile: "ep/audio/original.m4a")
        let audio = try #require(resolver.resolveViaProxy(song: song, targetQuality: .standard))
        #expect(audio.url == resolver.videoURL(forKey: "ep/audio/original.m4a"))
    }

    @Test func headersCarryTheBearerToken() {
        let headers = ProxyRequestHeaders.make(token: "abc.def")
        #expect(headers == ["Content-Type": "application/json", "Authorization": "Bearer abc.def"])
    }

    @Test func aMissingTokenIsAnEmptyBearer() {
        #expect(ProxyRequestHeaders.make(token: nil)["Authorization"] == "Bearer ")
    }
}
