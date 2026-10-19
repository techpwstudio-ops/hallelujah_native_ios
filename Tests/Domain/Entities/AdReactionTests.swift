import Testing
@testable import Hallelujah

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

/// `ads/ad_feedback.dart`: wire values, which verdicts mute, reason lists.
struct AdFeedbackTests {
    @Test func wireValues() {
        #expect(AdFeedbackKind.interested.wireValue == "interested")
        #expect(AdFeedbackKind.notInterested.wireValue == "not_interested")
        #expect(AdFeedbackKind.report.wireValue == "report")
        #expect(AdFeedbackKind.close.wireValue == "close")
    }

    @Test func onlyNotInterestedAndReportMute() {
        #expect(AdFeedbackKind.notInterested.mutes)
        #expect(AdFeedbackKind.report.mutes)
        #expect(!AdFeedbackKind.interested.mutes)
        #expect(!AdFeedbackKind.close.mutes)
    }

    @Test func reasonListsFollowTheKind() {
        #expect(AdFeedbackReason.reasons(for: .notInterested) == [.notRelevant, .seenTooOften, .dislikeBrand, .other])
        #expect(AdFeedbackReason.reasons(for: .report).count == 7)
        #expect(AdFeedbackReason.reasons(for: .report).last == .other)
        #expect(AdFeedbackReason.notRelevant.rawValue == "not_relevant")
    }
}
