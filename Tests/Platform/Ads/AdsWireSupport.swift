import Foundation
import Testing
@testable import Hallelujah

/// One request the repository sent, as the mock saw it.
struct SentRequest: Sendable {
    let path: String
    let query: [String: String]
    let body: [String: String]
}

/// Locks around a plain array: `MockURLProtocol`'s handler closure is
/// synchronous, so it can't `await` an actor.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [SentRequest] = []

    func add(_ entry: SentRequest) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var all: [SentRequest] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// The requests whose path ends in `suffix`, in the order they arrived.
    func requests(_ suffix: String) -> [SentRequest] {
        all.filter { $0.path.hasSuffix(suffix) }
    }
}

/// A device id nobody persists. The headers every request carries need one, and
/// the real store reads the Keychain.
private final class NoDeviceID: DeviceIDPersisting, @unchecked Sendable {
    func load() -> String? { nil }
    func save(_ deviceID: String?) {}
}

/// Test doubles for the ads wire: an `AdsRepository` on a mock session, a log of
/// what it sent, and ways to wait for fire-and-forget calls to land.
enum AdsWire {
    /// Headers with no App Check source behind them. The shared provider is wired
    /// to Firebase when the app that hosts the tests has configured it, which
    /// would put a real token fetch in front of every request.
    static let headers = RequestHeaderProvider(
        deviceIdentity: DeviceIdentityStore(persistence: NoDeviceID()),
        appCheckCache: AppCheckTokenCache(),
        deviceInfo: DeviceHeaderInfo(model: "test", appVersion: "0", buildNumber: "0", os: "ios")
    )

    /// `serving` answers `GET /ads/serve` with a 200 and that body, or with a
    /// 204 (no fill) when it returns nil; every other request is a 204.
    @MainActor
    static func makeRepository(
        log: RequestLog,
        serving: (@Sendable (SentRequest) -> Data?)? = nil
    ) -> AdsRepository {
        let session = MockURLProtocol.makeSession { request in
            let sent = SentRequest(
                path: request.url?.path ?? "",
                query: query(of: request),
                body: jsonBody(of: request)
            )
            log.add(sent)
            let served = sent.path.hasSuffix("/ads/serve") ? serving?(sent) : nil
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: served == nil ? 204 : 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, served ?? Data())
        }
        let client = HTTPClient(configuration: .staging, session: session, headerProvider: headers)
        return AdsRepository(client: client, membershipStore: MembershipStore(keyValueStore: InMemoryKeyValueStore()))
    }

    /// A served creative's JSON, the way the server sends it. `extra` adds or
    /// overrides fields (`skipAfterSec`, `lingerAfterDismiss`, …).
    static func servedBody(
        assetType: String,
        placement: String,
        token: String,
        assetUrl: String = "https://example.com/ad",
        extra: [String: Any] = [:]
    ) -> Data {
        var json: [String: Any] = [
            "adId": "ad-\(token)",
            "campaignId": "camp-\(token)",
            "placement": placement,
            "assetType": assetType,
            "assetUrl": assetUrl,
            "impressionToken": token,
        ]
        for (key, value) in extra { json[key] = value }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    /// A body sent through `URLSession` reaches a `URLProtocol` as a stream, not
    /// as `httpBody`.
    nonisolated static func jsonBody(of request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }

    nonisolated static func query(of request: URLRequest) -> [String: String] {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        var query: [String: String] = [:]
        for item in items where query[item.name] == nil {
            query[item.name] = item.value
        }
        return query
    }

    /// The reports are fire-and-forget, so a test waits for them to land. It
    /// fails when they do not, rather than carrying on to assertions that would
    /// then read as a wrong answer instead of a missing one.
    @MainActor
    static func waitForRequests(
        _ count: Int,
        in log: RequestLog,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitUntil("\(count) request(s) (saw \(log.all.count))", sourceLocation: sourceLocation) {
            log.all.count >= count
        }
    }

    /// Polls `condition` for up to `seconds`, recording an issue if it never holds.
    @MainActor
    static func waitUntil(
        _ what: String,
        seconds: Double = 5,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        let polls = Int(seconds * 50)
        for _ in 0 ..< polls where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if !condition() {
            Issue.record("gave up waiting for \(what) after \(seconds) s", sourceLocation: sourceLocation)
        }
    }
}
