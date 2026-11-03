import Foundation
import Testing
@testable import Hallelujah

/// `AudioEngine.playbackMilliseconds`, the rule behind `currentPlaybackMs()`.
struct PlaybackPositionRuleTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func theReadingIsUsedWhenNoSeekIsPending() {
        let positionMs = AudioEngine.playbackMilliseconds(reported: 12.5, current: 3, pendingSeek: nil, now: now)

        #expect(positionMs == 12_500)
    }

    @Test func aReadingFarFromAPendingSeekIsTheOldPosition() {
        let pending = (target: 60.0, until: now.addingTimeInterval(1.5))
        let positionMs = AudioEngine.playbackMilliseconds(reported: 3, current: 60, pendingSeek: pending, now: now)

        #expect(positionMs == 60_000)
    }

    @Test func aReadingNearAPendingSeekIsUsed() {
        let pending = (target: 60.0, until: now.addingTimeInterval(1.5))
        let positionMs = AudioEngine.playbackMilliseconds(reported: 60.4, current: 60, pendingSeek: pending, now: now)

        #expect(positionMs == 60_400)
    }

    @Test func afterTheWindowTheReadingWins() {
        let pending = (target: 60.0, until: now.addingTimeInterval(-1))
        let positionMs = AudioEngine.playbackMilliseconds(reported: 3, current: 60, pendingSeek: pending, now: now)

        #expect(positionMs == 3_000)
    }

    @Test func aNonFiniteReadingFallsBackToThePublishedPosition() {
        let positionMs = AudioEngine.playbackMilliseconds(reported: .nan, current: 7, pendingSeek: nil, now: now)

        #expect(positionMs == 7_000)
    }
}
