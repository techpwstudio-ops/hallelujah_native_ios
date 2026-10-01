import Foundation
import Testing
@testable import GHallelujah

/// Locks around a plain Int rather than using an actor: `MockURLProtocol`'s
/// handler closure is synchronous, so it can't `await` an actor.
final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// `.serialized`: every test in this file drives the same static
/// `MockURLProtocol.requestHandler`, so they can't run concurrently with
/// each other without clobbering it.
@Suite(.serialized)
struct HTTPClientTests {
    @Test func retriesTransportFailuresThenSucceeds() async throws {
        let counter = AttemptCounter()
        MockURLProtocol.requestHandler = { request in
            if counter.increment() < 3 {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let client = HTTPClient(configuration: .staging, session: MockURLProtocol.makeSession())
        let response = try await client.send(.geoCountry)

        #expect(response.statusCode == 200)
        #expect(counter.current == 3) // 2 failures + 1 success = HTTPClient.maxAttempts
    }

    @Test func doesNotRetryOnHTTPErrorStatus() async throws {
        let counter = AttemptCounter()
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = HTTPClient(configuration: .staging, session: MockURLProtocol.makeSession())
        let response = try await client.send(.geoCountry)

        #expect(response.statusCode == 500) // surfaced as a normal response, not thrown
        #expect(counter.current == 1) // never retried
    }

    @Test func forced401TriggersExactlyOneRefreshAndReplaysTheOriginalRequest() async throws {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.save(AuthTokens(
            accessToken: "old-access",
            refreshToken: "refresh-1",
            accessTokenExpiry: .distantFuture,
            refreshTokenExpiry: .distantFuture
        ))

        let originalCallCount = AttemptCounter()
        let refreshCallCount = AttemptCounter()
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/auth/token/refresh") == true {
                refreshCallCount.increment()
                let json = #"{"token":"new-access","refreshToken":"new-refresh","accessTokenExpiry":"2099-01-01T00:00:00Z","refreshTokenExpiry":"2099-01-01T00:00:00Z"}"#
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(json.utf8))
            }
            let statusCode = originalCallCount.increment() == 1 ? 401 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let mockSession = MockURLProtocol.makeSession()
        let refreshClient = HTTPClient(configuration: .staging, session: mockSession)
        let session = Session(tokenStore: tokenStore, refreshClient: refreshClient)
        let authenticatedClient = HTTPClient(configuration: .staging, authProvider: session, session: mockSession)

        let response = try await authenticatedClient.send(.geoCountry)

        #expect(response.statusCode == 200)
        #expect(originalCallCount.current == 2) // original 401 + replay
        #expect(refreshCallCount.current == 1) // single-flight: exactly one refresh
    }

    @Test func concurrentRefreshCallsShareASingleInFlightRequest() async throws {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.save(AuthTokens(
            accessToken: "old-access",
            refreshToken: "refresh-1",
            accessTokenExpiry: .distantPast,
            refreshTokenExpiry: .distantFuture
        ))

        let refreshCallCount = AttemptCounter()
        MockURLProtocol.requestHandler = { request in
            refreshCallCount.increment()
            let json = #"{"token":"new-access","refreshToken":"new-refresh","accessTokenExpiry":"2099-01-01T00:00:00Z","refreshTokenExpiry":"2099-01-01T00:00:00Z"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let refreshClient = HTTPClient(configuration: .staging, session: MockURLProtocol.makeSession())
        let session = Session(tokenStore: tokenStore, refreshClient: refreshClient)

        async let first = session.refreshIfNeeded()
        async let second = session.refreshIfNeeded()
        async let third = session.refreshIfNeeded()
        _ = try await (first, second, third)

        #expect(refreshCallCount.current == 1)
    }

    @Test func logsOutWhenRefreshFails() async throws {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.save(AuthTokens(
            accessToken: "old-access",
            refreshToken: "bad-refresh",
            accessTokenExpiry: .distantPast,
            refreshTokenExpiry: .distantFuture
        ))

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let refreshClient = HTTPClient(configuration: .staging, session: MockURLProtocol.makeSession())
        let session = Session(tokenStore: tokenStore, refreshClient: refreshClient)

        await #expect(throws: (any Error).self) {
            try await session.refreshIfNeeded()
        }
        #expect(tokenStore.load() == nil)
    }
}
