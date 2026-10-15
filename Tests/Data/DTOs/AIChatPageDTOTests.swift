import Foundation
import Testing
@testable import GHallelujah

struct AIChatPageDTOTests {
    @Test func messagesKeyAndCursorAreAccepted() throws {
        let json = """
        {"data":{"messages":[{"id":"m1","role":"user","content":"hi","createdAt":"2026-01-01T00:00:00Z"}],
                 "cursor":"abc","hasMore":true}}
        """
        let decoded = try JSONDecoder().decode(AIMessagesResponseDTO.self, from: Data(json.utf8))
        let page = decoded.toDomain()
        #expect(page.items.count == 1)
        #expect(page.hasMore)
        #expect(page.nextCursor == "abc")
    }

    @Test func itemsKeyAndNextCursorAreAccepted() throws {
        let json = """
        {"data":{"items":[{"id":"m1","role":"assistant","content":"yo"}],"nextCursor":"zzz","hasMore":false}}
        """
        let page = try JSONDecoder().decode(AIMessagesResponseDTO.self, from: Data(json.utf8)).toDomain()
        #expect(page.items.count == 1)
        #expect(page.nextCursor == "zzz")
        #expect(!page.hasMore)
    }

    @Test func conversationsKeyAndPageAreAccepted() throws {
        let json = """
        {"data":{"conversations":[{"id":"c1","title":"T"}],"hasMore":true,"page":2}}
        """
        let page = try JSONDecoder().decode(AIConversationsResponseDTO.self, from: Data(json.utf8)).toDomain()
        #expect(page.items.first?.id == "c1")
        #expect(page.page == 2)
        #expect(page.hasMore)
    }
}
