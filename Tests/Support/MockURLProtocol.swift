import Foundation

/// Intercepts every request on a session made by `makeSession(handler:)` and
/// hands back whatever that session's handler returns, instead of touching the
/// network.
///
/// Each session carries its own handler, so suites running in parallel can't see
/// each other's requests. The session tags its requests with an id header, which
/// is how the protocol (a class `URLSession` instantiates itself) finds the right
/// handler; the header is stripped before the handler sees the request.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let sessionHeader = "X-Mock-Session-ID"
    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func makeSession(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        handlerLock.lock()
        handlers[id] = handler
        handlerLock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [sessionHeader: id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        let id = request.value(forHTTPHeaderField: Self.sessionHeader)
        request.setValue(nil, forHTTPHeaderField: Self.sessionHeader)

        Self.handlerLock.lock()
        let handler = id.flatMap { Self.handlers[$0] }
        Self.handlerLock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
