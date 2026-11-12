import Foundation
import Testing
@testable import Hallelujah

struct PlayerVideoSourceTests {
    private struct StubTokens: AuthTokenProviding {
        let token: String?

        func currentAccessToken() async -> String? { token }

        func refreshIfNeeded() async throws -> AuthTokens { throw CancellationError() }
    }

    private func source(token: String? = "abc.def") -> PlayerVideoSource {
        PlayerVideoSource(
            proxyBaseURL: URL(string: "https://api.example.com/api")!,
            tokenProvider: StubTokens(token: token)
        )
    }

    @Test func aSongWithAVideoKeyGetsItsProxyURL() {
        let song = Song.fixture(videoFile: "ep/video-song/1-silent/original.mp4")
        #expect(
            source().url(for: song)?.absoluteString
                == "https://api.example.com/api/proxy?path=ep/video-song/1-silent/original.mp4"
        )
    }

    @Test func aSongWithoutAVideoKeyHasNoURL() {
        #expect(source().url(for: .fixture()) == nil)
        #expect(source().url(for: .fixture(videoFile: "   ")) == nil)
    }

    @Test func aChosenVariantIsFetchedBesideTheOriginal() {
        let song = Song.fixture(videoFile: "ep/video-song/1-silent/original.mp4")
        let choice = VideoQualityChoice(quality: .p720, variantFileName: "720p.mp4")
        #expect(
            source().url(for: song, choice: choice)?.absoluteString
                == "https://api.example.com/api/proxy?path=ep/video-song/1-silent/720p.mp4"
        )
    }

    @Test func theOriginalChoiceAndNoChoiceBothPlayTheVideoFile() {
        let song = Song.fixture(videoFile: "ep/video-song/1-silent/original.mp4")
        let expected = "https://api.example.com/api/proxy?path=ep/video-song/1-silent/original.mp4"
        #expect(source().url(for: song, choice: .original)?.absoluteString == expected)
        #expect(source().url(for: song, choice: nil)?.absoluteString == expected)
    }

    @Test func aVariantOfASongWithoutAVideoKeyHasNoURL() {
        let choice = VideoQualityChoice(quality: .p480, variantFileName: "480p.mp4")
        #expect(source().url(for: .fixture(), choice: choice) == nil)
    }

    @Test func aBareKeyGetsTheVariantNameAlone() {
        let song = Song.fixture(videoFile: "original.mp4")
        let choice = VideoQualityChoice(quality: .p480, variantFileName: "480p.mp4")
        #expect(source().url(for: song, choice: choice)?.absoluteString == "https://api.example.com/api/proxy?path=480p.mp4")
    }

    @Test func theHeadersCarryTheCurrentToken() async {
        let headers = await source(token: "tok-1").headers()
        #expect(headers == ["Content-Type": "application/json", "Authorization": "Bearer tok-1"])
    }

    @Test func aMissingTokenIsAnEmptyBearer() async {
        let headers = await source(token: nil).headers()
        #expect(headers["Authorization"] == "Bearer ")
    }
}
