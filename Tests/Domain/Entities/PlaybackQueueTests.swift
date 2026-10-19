import Testing
@testable import Hallelujah

struct PlaybackQueueTests {
    private let source = QueueAttribution(playerType: .companyPlaylist, id: "p1", title: "Mix")

    @Test func currentSongFollowsIndex() {
        let songs = [Song.fixture(id: "a"), Song.fixture(id: "b")]
        #expect(PlaybackQueue(songs: songs, currentIndex: 1, source: source).currentSong?.id == "b")
    }

    @Test func currentSongIsNilWhenIndexIsOutOfRange() {
        #expect(PlaybackQueue(songs: [], currentIndex: 0, source: source).currentSong == nil)
        #expect(PlaybackQueue(songs: [Song.fixture()], currentIndex: 3, source: source).currentSong == nil)
        #expect(PlaybackQueue(songs: [Song.fixture()], currentIndex: -1, source: source).currentSong == nil)
    }

    @Test func playerIDCombinesTypeAndId() {
        #expect(source.playerID == "companyPlaylist-p1")
        #expect(QueueAttribution(playerType: .home, id: nil, title: "").playerID == "home-")
    }

    @Test(arguments: [
        (PlayerType.companyPlaylist, true), (.album, true), (.season, true),
        (.genre, true), (.userPlaylist, true), (.creator, true),
        (.home, false), (.search, false), (.invite, false), (.download, false), (.favourite, false)
    ])
    func queueableTypes(type: PlayerType, expected: Bool) {
        #expect(type.isQueueable == expected)
    }

    @Test func repeatModeCyclesOffAllOneOff() {
        #expect(RepeatMode.off.next == .all)
        #expect(RepeatMode.all.next == .one)
        #expect(RepeatMode.one.next == .off)
    }
}
