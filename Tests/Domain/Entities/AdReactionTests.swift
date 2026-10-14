import Testing
@testable import GHallelujah

/// `ads/ad_reaction.dart`: wire values and the toggle rule.
struct AdReactionTests {
    @Test func wireValuesMatchTheBackend() {
        #expect(AdReaction.like.wireValue == "like")
        #expect(AdReaction.dislike.wireValue == "dislike")
        #expect(AdReaction.clearWireValue == "none")
    }

    @Test func pressingTheLitThumbTakesItBack() {
        #expect(AdReaction.next(current: .like, tapped: .like) == nil)
        #expect(AdReaction.next(current: .dislike, tapped: .dislike) == nil)
    }

    @Test func pressingTheOtherThumbSwitches() {
        #expect(AdReaction.next(current: .like, tapped: .dislike) == .dislike)
        #expect(AdReaction.next(current: nil, tapped: .like) == .like)
    }
}
