import Foundation
import Testing
@testable import GHallelujah

struct VerseOfDayDTOTests {
    @Test func likedComesFromFavouriteRowsWhenPresent() throws {
        let liked = #"{"id":"v1","favoriteVerseOfDays":[{"id":"f"}],"isLinked":false}"#
        let notLiked = #"{"id":"v1","favoriteVerseOfDays":[],"isLinked":true}"#
        #expect(try JSONDecoder().decode(VerseOfDayDTO.self, from: Data(liked.utf8)).toDomain().isLiked)
        #expect(try !JSONDecoder().decode(VerseOfDayDTO.self, from: Data(notLiked.utf8)).toDomain().isLiked)
    }

    @Test func likedFallsBackToIsLinked() throws {
        let json = #"{"id":"v1","isLinked":true}"#
        #expect(try JSONDecoder().decode(VerseOfDayDTO.self, from: Data(json.utf8)).toDomain().isLiked)
    }

    @Test func commentLikedComesFromLikeRows() throws {
        let json = #"{"id":"c1","verseOfDayId":"v1","content":"x","verseOfDayCommentLikes":[{"id":"l"}],"userId":"u1"}"#
        let comment = try JSONDecoder().decode(VerseOfDayCommentDTO.self, from: Data(json.utf8)).toDomain()
        #expect(comment.isLiked)
        #expect(comment.userId == "u1")
    }

    @Test func updatingCountsKeepsEverythingElse() {
        let verse = VerseOfDay(
            id: "v", title: "t", deliveryStatus: nil, image: nil, backgroundImage: nil, verseId: nil,
            languageName: "English", verseText: "text", bookName: "John", bookNumber: 43,
            chapterNumber: 3, verseNumber: 16, likes: 1, shares: 2, comments: 3, isLiked: true,
            scheduledAt: nil, sentAt: nil, createdAt: nil, updatedAt: nil
        )
        let updated = verse.updatingCounts(likes: 9, comments: nil)
        #expect(updated.likes == 9)
        #expect(updated.comments == 3)
        #expect(updated.verseText == "text")
        #expect(updated.isLiked)
    }
}
