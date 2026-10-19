import Foundation
import Testing
@testable import Hallelujah

struct SessionPolicyTests {
    @Test func refreshFiresTwoMinutesBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiry = now.addingTimeInterval(600)
        #expect(Session.monitorDelay(accessExpiry: expiry, now: now) == 480)
    }

    @Test func insideTheWindowFiresAfterAShortPause() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Session.monitorDelay(accessExpiry: now.addingTimeInterval(60), now: now) == 2)
        #expect(Session.monitorDelay(accessExpiry: now.addingTimeInterval(-10), now: now) == 2)
    }

    @Test func onlyAServerRefusalEndsTheSession() {
        #expect(Session.endsSession(after: SessionError.refreshFailed(statusCode: 401)))
        #expect(Session.endsSession(after: SessionError.refreshFailed(statusCode: 403)))
        #expect(Session.endsSession(after: SessionError.refreshFailed(statusCode: 404)))
        #expect(Session.endsSession(after: SessionError.refreshTokenExpired))
        #expect(Session.endsSession(after: SessionError.noRefreshToken))
    }

    @Test func networkTroubleKeepsTheSession() {
        #expect(!Session.endsSession(after: SessionError.refreshFailed(statusCode: 500)))
        #expect(!Session.endsSession(after: SessionError.refreshFailed(statusCode: 429)))
        #expect(!Session.endsSession(after: APIError.transport(URLError(.notConnectedToInternet))))
        #expect(!Session.endsSession(after: URLError(.timedOut)))
    }

    @Test func authTokensDecodeFractionalSecondExpiries() throws {
        let json = #"{"token":"a","refreshToken":"r","accessTokenExpiry":"2099-01-01T00:00:00.000Z","refreshTokenExpiry":"2099-02-01T00:00:00Z"}"#
        let tokens = try JSONDecoder.authTokens.decode(AuthTokens.self, from: Data(json.utf8))
        #expect(tokens.accessToken == "a")
        #expect(tokens.accessTokenExpiry > Date())
        #expect(tokens.refreshTokenExpiry > tokens.accessTokenExpiry)
    }
}
