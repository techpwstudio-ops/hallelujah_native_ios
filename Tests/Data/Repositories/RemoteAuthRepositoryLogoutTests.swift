import Foundation
import Testing
@testable import Hallelujah

/// Locks around a plain array: `MockURLProtocol`'s handler closure is
/// synchronous, so it can't `await` an actor.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    var requestCount: Int {
        all.filter { $0 == "request" }.count
    }
}

/// `RemoteAuthRepository.logout(reason:)` flushes analytics first — before the
/// logout endpoint (which may revoke the token) and before `session.logout()`
/// (which clears it) — so the upload is authenticated.
@MainActor
struct RemoteAuthRepositoryLogoutTests {
    /// Answers 200 and records each request in `log`.
    private func makeMockSession(log: EventLog) -> URLSession {
        MockURLProtocol.makeSession { request in
            log.add("request")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
    }

    private func makeRepository(
        log: EventLog,
        prepareForSignOut: @escaping @Sendable (Session) async -> Void
    ) throws -> (repository: RemoteAuthRepository, session: Session) {
        let tokenStore = InMemoryTokenStore()
        try tokenStore.save(AuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            accessTokenExpiry: Date().addingTimeInterval(3600),
            refreshTokenExpiry: .distantFuture
        ))
        let session = Session(
            tokenStore: tokenStore,
            refreshClient: HTTPClient(configuration: .staging, session: makeMockSession(log: log))
        )
        let currentUserStore = CurrentUserStore(keyValueStore: InMemoryKeyValueStore())
        let repository = RemoteAuthRepository(
            client: HTTPClient(configuration: .staging, session: makeMockSession(log: log)),
            session: session,
            currentUserStore: currentUserStore,
            membershipStore: MembershipStore(keyValueStore: InMemoryKeyValueStore()),
            appCheck: UnavailableAppCheckProvider(),
            configuration: .staging,
            realtimeConnectionManager: RealtimeConnectionManager(
                configuration: .staging,
                authProvider: session,
                dispatcher: RealtimeEventDispatcher(currentUserStore: currentUserStore, eventBus: RealtimeEventBus())
            ),
            prepareForSignOut: { await prepareForSignOut(session) }
        )
        return (repository, session)
    }

    /// The audit entry is sent from a detached task, so it can land after
    /// `logout` returns — wait for it so the assertions see the full log.
    private func waitForRequests(_ count: Int, in log: EventLog) async {
        for _ in 0..<60 where log.requestCount < count {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func preparesForSignOutBeforeAnyRequestIsSent() async throws {
        let log = EventLog()
        let (repository, _) = try makeRepository(log: log) { _ in log.add("prepare") }

        await repository.logout(reason: "manual")
        await waitForRequests(2, in: log)

        #expect(log.all.first == "prepare")
        #expect(log.requestCount >= 1) // the logout endpoint is still called
    }

    @Test func preparesForSignOutWhileTheSessionStillHoldsItsToken() async throws {
        let log = EventLog()
        let (repository, session) = try makeRepository(log: log) { session in
            log.add("token:\(await session.currentAccessToken() ?? "none")")
        }

        await repository.logout(reason: "manual")
        await waitForRequests(2, in: log)

        #expect(log.all.first == "token:access")
        #expect(await session.currentAccessToken() == nil) // and logout still clears it
    }
}
