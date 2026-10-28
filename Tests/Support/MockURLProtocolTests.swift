import Foundation
import Testing

/// The helper every networking test leans on: suites run in parallel, so two
/// sessions must never see each other's requests.
struct MockURLProtocolTests {
    private func fetch(_ session: URLSession) async throws -> String {
        let (data, _) = try await session.data(from: URL(string: "https://example.test/ping")!)
        return String(decoding: data, as: UTF8.self)
    }

    private func makeSession(answering body: String) -> URLSession {
        MockURLProtocol.makeSession { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    @Test func eachSessionGetsItsOwnHandler() async throws {
        let first = makeSession(answering: "first")
        let second = makeSession(answering: "second")

        // Interleaved on purpose: the later-created session must not win.
        #expect(try await fetch(first) == "first")
        #expect(try await fetch(second) == "second")
        #expect(try await fetch(first) == "first")
    }

    @Test func theHandlerSeesTheRequestWithoutTheRoutingHeader() async throws {
        let seenHeaders = AttemptCounter() // counts requests that still carried the routing header
        let session = MockURLProtocol.makeSession { request in
            if request.value(forHTTPHeaderField: "X-Mock-Session-ID") != nil { seenHeaders.increment() }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        _ = try await fetch(session)

        #expect(seenHeaders.current == 0)
    }
}
