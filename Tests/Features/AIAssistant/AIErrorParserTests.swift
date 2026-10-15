import Foundation
import Testing
@testable import GHallelujah

struct AIErrorParserTests {
    @Test func cancellationIsSilent() {
        #expect(AIErrorParser.parse(CancellationError()) == "")
        #expect(AIErrorParser.parse(URLError(.cancelled)) == "")
    }

    @Test func timeoutMessage() {
        #expect(AIErrorParser.parse(URLError(.timedOut)) == "Request timed out. Please try again.")
    }

    @Test func connectionMessageDependsOnReachability() {
        let offline = AIErrorParser.parse(URLError(.notConnectedToInternet), isOnline: false)
        #expect(offline == "No internet connection. Please check your connection and try again.")
        let online = AIErrorParser.parse(URLError(.notConnectedToInternet), isOnline: true)
        #expect(online == "Connection failed. Please try again.")
    }

    @Test func statusCodesMapToCopy() {
        #expect(AIErrorParser.message(forStatus: 401) == "Session expired. Please sign in again.")
        #expect(AIErrorParser.message(forStatus: 429) == "You're sending messages too quickly. Please slow down and try again.")
        #expect(AIErrorParser.message(forStatus: 503) == "Something went wrong on our end. Please try again later.")
        #expect(AIErrorParser.message(forStatus: 418) == AIErrorParser.genericMessage)
        #expect(AIErrorParser.parse(AIChatRepositoryError.unexpectedStatus(404)) == "Content not found.")
    }
}
