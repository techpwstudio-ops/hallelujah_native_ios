import Foundation
import Testing
@testable import Hallelujah

private final class CountingAppCheckSource: AppCheckTokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String?]
    private(set) var fetches = 0

    init(_ tokens: [String?]) { queue = tokens }

    func currentToken() async -> String? { next() }

    /// Synchronous so the lock isn't taken from an async context.
    private func next() -> String? {
        lock.lock()
        defer { lock.unlock() }
        fetches += 1
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}

private final class InMemoryDeviceIDPersistence: DeviceIDPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ stored: String? = nil) { self.stored = stored }
    func load() -> String? { lock.lock(); defer { lock.unlock() }; return stored }
    func save(_ deviceID: String?) { lock.lock(); defer { lock.unlock() }; stored = deviceID }
}

struct RequestHeaderProviderTests {
    private let info = DeviceHeaderInfo(model: "iPhone15,2", appVersion: "2.4.0", buildNumber: "87", os: "ios")

    @Test func sendsEverythingBuildHeadersSends() async {
        let provider = RequestHeaderProvider(
            deviceIdentity: DeviceIdentityStore(persistence: InMemoryDeviceIDPersistence("dev-1")),
            appCheckCache: AppCheckTokenCache(source: CountingAppCheckSource(["tok"])),
            deviceInfo: info
        )
        let headers = await provider.headers()
        #expect(headers["app-check-token"] == "tok")
        #expect(headers["device-id"] == "dev-1")
        #expect(headers["device-model"] == "iPhone15,2")
        #expect(headers["os"] == "ios")
        #expect(headers["app-version"] == "2.4.0")
        #expect(headers["build-number"] == "87")
    }

    @Test func missingDeviceIDAndAppCheckAreEmptyStrings() async {
        let provider = RequestHeaderProvider(
            deviceIdentity: DeviceIdentityStore(persistence: InMemoryDeviceIDPersistence()),
            appCheckCache: AppCheckTokenCache(),
            deviceInfo: info
        )
        let headers = await provider.headers()
        #expect(headers["app-check-token"] == "")
        #expect(headers["device-id"] == "")
    }

    @Test func appCheckTokenIsReusedForFortyFiveMinutes() async {
        let source = CountingAppCheckSource(["first", "second"])
        let cache = AppCheckTokenCache(source: source)
        let start = Date(timeIntervalSince1970: 1_000_000)

        #expect(await cache.currentToken(now: start) == "first")
        #expect(await cache.currentToken(now: start.addingTimeInterval(44 * 60)) == "first")
        #expect(source.fetches == 1)
        #expect(await cache.currentToken(now: start.addingTimeInterval(45 * 60 + 1)) == "second")
        #expect(source.fetches == 2)
    }

    @Test func failedRefreshKeepsServingThePreviousToken() async {
        let source = CountingAppCheckSource(["first", nil])
        let cache = AppCheckTokenCache(source: source)
        let start = Date(timeIntervalSince1970: 1_000_000)

        #expect(await cache.currentToken(now: start) == "first")
        #expect(await cache.currentToken(now: start.addingTimeInterval(3_600)) == "first")
    }

    @Test func resetForcesAFreshFetch() async {
        let source = CountingAppCheckSource(["a", "b"])
        let cache = AppCheckTokenCache(source: source)
        #expect(await cache.currentToken() == "a")
        cache.reset()
        #expect(await cache.currentToken() == "b")
    }
}

struct DeviceIdentityStoreTests {
    @Test func nilOrEmptyDoesNotOverwriteTheStoredID() {
        let store = DeviceIdentityStore(persistence: InMemoryDeviceIDPersistence("dev-1"))
        store.update(nil)
        store.update("")
        #expect(store.deviceID == "dev-1")
    }

    @Test func newIDIsPersisted() {
        let persistence = InMemoryDeviceIDPersistence()
        let store = DeviceIdentityStore(persistence: persistence)
        #expect(store.deviceID == nil)
        store.update("dev-2")
        #expect(store.deviceID == "dev-2")
        #expect(persistence.load() == "dev-2")
    }
}
