import Testing
import UIKit
@testable import Hallelujah

struct CarPlayNowPlayingTests {
    private let source = QueueAttribution(playerType: .home, id: nil, title: "")

    // MARK: - Button row

    private func row(
        isFavorited: Bool = false,
        isShuffled: Bool = false,
        repeatMode: RepeatMode = .off,
        offersSleepTimer: Bool = false,
        isSleepTimerRunning: Bool = false
    ) -> [CarPlayNowPlayingButton] {
        CarPlayNowPlayingButton.row(
            isFavorited: isFavorited,
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            offersSleepTimer: offersSleepTimer,
            isSleepTimerRunning: isSleepTimerRunning
        )
    }

    private func slot(
        _ kind: CarPlayNowPlayingButton.Kind,
        in buttons: [CarPlayNowPlayingButton]
    ) -> CarPlayNowPlayingButton? {
        buttons.first { $0.kind == kind }
    }

    @Test func idleRowHasLikeShuffleAndRepeatInOrderAllUnlit() {
        let buttons = row()

        #expect(buttons.map(\.kind) == [.like, .shuffle, .repeatMode])
        #expect(buttons.map(\.symbol) == ["heart", "shuffle", "repeat"])
        #expect(buttons.allSatisfy { !$0.isSelected })
    }

    @Test func likeFillsAndLightsWhenTheSongIsFavourited() {
        let like = slot(.like, in: row(isFavorited: true))

        #expect(like == CarPlayNowPlayingButton(kind: .like, symbol: "heart.fill", isSelected: true))
    }

    @Test func shuffleLightsWhenShuffled() {
        #expect(slot(.shuffle, in: row(isShuffled: true))?.isSelected == true)
        #expect(slot(.shuffle, in: row(isShuffled: false))?.isSelected == false)
    }

    @Test func repeatShowsItsModeThroughGlyphAndLitState() {
        let off = slot(.repeatMode, in: row(repeatMode: .off))
        let all = slot(.repeatMode, in: row(repeatMode: .all))
        let one = slot(.repeatMode, in: row(repeatMode: .one))

        #expect(off == CarPlayNowPlayingButton(kind: .repeatMode, symbol: "repeat", isSelected: false))
        #expect(all == CarPlayNowPlayingButton(kind: .repeatMode, symbol: "repeat", isSelected: true))
        #expect(one == CarPlayNowPlayingButton(kind: .repeatMode, symbol: "repeat.1", isSelected: true))
    }

    @Test func sleepTimerButtonExistsOnlyWhenThePlanOffersIt() {
        #expect(slot(.sleepTimer, in: row(offersSleepTimer: false)) == nil)
        #expect(slot(.sleepTimer, in: row(offersSleepTimer: true)) != nil)
        // A timer started on the phone before the plan lapsed must not bring the button back.
        #expect(slot(.sleepTimer, in: row(offersSleepTimer: false, isSleepTimerRunning: true)) == nil)
    }

    @Test func sleepTimerComesLastAndLightsWhileRunning() {
        let idle = row(offersSleepTimer: true)
        let running = row(offersSleepTimer: true, isSleepTimerRunning: true)

        #expect(idle.last == CarPlayNowPlayingButton(kind: .sleepTimer, symbol: "moon.zzz", isSelected: false))
        #expect(running.last == CarPlayNowPlayingButton(kind: .sleepTimer, symbol: "moon.zzz.fill", isSelected: true))
    }

    @Test func fullestRowFitsCarPlaysFiveSlots() {
        let fullest = row(
            isFavorited: true, isShuffled: true, repeatMode: .one,
            offersSleepTimer: true, isSleepTimerRunning: true
        )

        #expect(fullest.count <= 5)
    }

    @Test func rowDiffersWheneverAnythingItShowsChanges() {
        let base = row()

        #expect(row() == base)
        #expect(row(isFavorited: true) != base)
        #expect(row(isShuffled: true) != base)
        #expect(row(repeatMode: .all) != base)
        #expect(row(repeatMode: .one) != row(repeatMode: .all))
        #expect(row(offersSleepTimer: true) != base)
        #expect(row(offersSleepTimer: true, isSleepTimerRunning: true) != row(offersSleepTimer: true))
    }

    /// The controller falls back to an empty image for an unknown symbol, which
    /// would leave a blank button in the car — so a typo has to fail here.
    @Test func everyGlyphIsARealSFSymbol() {
        let buttons = [
            row(offersSleepTimer: true),
            row(isFavorited: true, repeatMode: .one, offersSleepTimer: true, isSleepTimerRunning: true),
        ].flatMap { $0 }

        for button in buttons {
            #expect(UIImage(systemName: button.symbol) != nil, "\(button.symbol) is not an SF Symbol")
        }
    }

    // MARK: - Queue window

    private func queue(count: Int, current: Int) -> PlaybackQueue {
        PlaybackQueue(songs: (0..<count).map { Song.fixture(id: "s\($0)") }, currentIndex: current, source: source)
    }

    @Test func queueWindowStartsAtTheCurrentSongAndDropsWhatAlreadyPlayed() throws {
        let window = try #require(CarPlayQueueWindow(queue: queue(count: 6, current: 2), limit: 100))

        #expect(window.startIndex == 2)
        #expect(window.songs.map(\.id) == ["s2", "s3", "s4", "s5"])
    }

    @Test func queueWindowIsCappedAtTheLimitWithTheCurrentSongFirst() throws {
        let window = try #require(CarPlayQueueWindow(queue: queue(count: 10, current: 3), limit: 4))

        #expect(window.startIndex == 3)
        #expect(window.songs.map(\.id) == ["s3", "s4", "s5", "s6"])
    }

    @Test func queueWindowOfTheLastSongHoldsOnlyThatSong() throws {
        let window = try #require(CarPlayQueueWindow(queue: queue(count: 3, current: 2), limit: 100))

        #expect(window.startIndex == 2)
        #expect(window.songs.map(\.id) == ["s2"])
    }

    @Test func queueWindowOffsetsMapBackToQueueIndices() throws {
        let full = queue(count: 8, current: 5)
        let window = try #require(CarPlayQueueWindow(queue: full, limit: 100))

        for (offset, song) in window.songs.enumerated() {
            #expect(full.songs[window.startIndex + offset].id == song.id)
        }
    }

    @Test func queueWindowIsNilWhenTheQueueIsEmptyOrPointsAtNoSong() {
        #expect(CarPlayQueueWindow(queue: queue(count: 0, current: 0), limit: 100) == nil)
        #expect(CarPlayQueueWindow(queue: queue(count: 3, current: 3), limit: 100) == nil)
        #expect(CarPlayQueueWindow(queue: queue(count: 3, current: -1), limit: 100) == nil)
    }

    @Test func queueWindowIsNilForANonPositiveLimit() {
        #expect(CarPlayQueueWindow(queue: queue(count: 3, current: 0), limit: 0) == nil)
    }
}
