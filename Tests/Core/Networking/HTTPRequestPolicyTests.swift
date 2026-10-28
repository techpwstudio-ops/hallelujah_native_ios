import Foundation
import Testing
@testable import Hallelujah

struct HTTPRequestPolicyTests {
    // MARK: silent

    @Test func backgroundCallsAreSilent() {
        for path in [
            "/ads/serve?placement=home",
            "/ads/track/impression",
            "/analytics/track",
            "/geo/country",
            "/library/items/ids",
            "/deep-link/abc123/validate",
            "/song/42",
            "/song/42/related?limit=10",
            "/book/search?q=love",
            "/system/public/audit/logs",
        ] {
            #expect(HTTPRequestPolicy.isSilent(path: path), "\(path) should be silent")
        }
    }

    @Test func userVisibleCallsAreNotSilent() {
        for path in [
            "/users/me",
            "/library/items?page=1&type=all",
            "/song/42/report",
            "/song/toggle/favorite/42?value=true",
            "/dashboard/init",
            "/v2/home/layout/all?withSections=6",
        ] {
            #expect(!HTTPRequestPolicy.isSilent(path: path), "\(path) should toast on failure")
        }
    }

    // MARK: retry

    @Test func nonIdempotentRequestsOptOutOfRetry() {
        #expect(!HTTPRequestPolicy.allowsRetry(method: .post, path: "/ai/conversations"))
        #expect(HTTPRequestPolicy.allowsRetry(method: .get, path: "/ai/conversations"))
        #expect(HTTPRequestPolicy.allowsRetry(method: .post, path: "/ai/conversations/9/messages"))
        #expect(HTTPRequestPolicy.allowsRetry(method: .post, path: "/library/user-playlist"))
    }

    /// GETs that flip server state: a resend after a lost response undoes the change.
    @Test func userPlaylistTogglesAreNeverRetried() {
        #expect(!HTTPRequestPolicy.allowsRetry(method: .get, path: "/library/user-playlist/p1/visibility"))
        #expect(!HTTPRequestPolicy.allowsRetry(method: .get, path: "/library/user-playlist/p1/follow"))
        #expect(HTTPRequestPolicy.allowsRetry(method: .get, path: "/library/user-playlist/p1"))
        #expect(HTTPRequestPolicy.allowsRetry(method: .get, path: "/library/user-playlist/p1/songs?page=2"))
    }

    // MARK: toasts

    @Test func rateLimitAndServerErrorsGetGenericToasts() {
        #expect(HTTPRequestPolicy.responseToast(statusCode: 429) == "Too many requests. Please try again later.")
        #expect(HTTPRequestPolicy.responseToast(statusCode: 500) == "Something went wrong. Please try again.")
        #expect(HTTPRequestPolicy.responseToast(statusCode: 503) == "Something went wrong. Please try again.")
        #expect(HTTPRequestPolicy.responseToast(statusCode: 404) == nil)
        #expect(HTTPRequestPolicy.responseToast(statusCode: 200) == nil)
    }

    @Test func offlineAndTimeoutMessagesDiffer() {
        #expect(HTTPRequestPolicy.transportToast(for: URLError(.notConnectedToInternet)) == UserFacingError.offline)
        #expect(HTTPRequestPolicy.transportToast(for: URLError(.timedOut)) == "Connection timeout. Please try again.")
    }

    // MARK: error body normalisation

    private func message(in data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["message"] as? String
    }

    @Test func jsonObjectErrorBodiesAreLeftAlone() {
        let body = Data(#"{"message":"Nope","code":"x"}"#.utf8)
        #expect(HTTPRequestPolicy.normalisedErrorBody(body, statusCode: 400) == nil)
    }

    @Test func successBodiesAreNeverTouched() {
        #expect(HTTPRequestPolicy.normalisedErrorBody(Data("plain".utf8), statusCode: 200) == nil)
        #expect(HTTPRequestPolicy.normalisedErrorBody(Data("[1,2]".utf8), statusCode: 204) == nil)
    }

    @Test func plainTextRateLimitBodyBecomesTheMessage() {
        let body = Data("Too many requests from this IP, please try again later.".utf8)
        let normalised = HTTPRequestPolicy.normalisedErrorBody(body, statusCode: 429)
        #expect(message(in: normalised) == "Too many requests from this IP, please try again later.")
    }

    @Test func htmlErrorPagesFallBackToTheGenericMessage() {
        let body = Data("<html><body>502 Bad Gateway</body></html>".utf8)
        #expect(message(in: HTTPRequestPolicy.normalisedErrorBody(body, statusCode: 502)) == "Something went wrong. Please try again.")
    }

    @Test func emptyBodiesFallBackByStatus() {
        #expect(message(in: HTTPRequestPolicy.normalisedErrorBody(Data(), statusCode: 504)) == "Something went wrong. Please try again.")
        #expect(message(in: HTTPRequestPolicy.normalisedErrorBody(Data(), statusCode: 429)) == "Too many requests. Please try again later.")
        #expect(message(in: HTTPRequestPolicy.normalisedErrorBody(Data(), statusCode: 418)) == "Request failed. Please try again.")
    }

    @Test func overlongTextIsNotUsedAsAMessage() {
        let body = Data(String(repeating: "a", count: 301).utf8)
        #expect(message(in: HTTPRequestPolicy.normalisedErrorBody(body, statusCode: 400)) == "Request failed. Please try again.")
    }

    @Test func nonObjectJSONIsKeptUnderRaw() throws {
        let normalised = try #require(HTTPRequestPolicy.normalisedErrorBody(Data("[1,2]".utf8), statusCode: 400))
        let object = try #require(try JSONSerialization.jsonObject(with: normalised) as? [String: Any])
        #expect(object["message"] as? String == "Request failed. Please try again.")
        #expect((object["raw"] as? [Int]) == [1, 2])
    }
}
