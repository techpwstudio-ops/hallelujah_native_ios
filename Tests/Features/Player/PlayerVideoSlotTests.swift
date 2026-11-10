import Testing
@testable import Hallelujah

@MainActor
struct PlayerVideoSlotTests {
    @Test(arguments: [
        // mode shows video, song has a source, audio is playing this song -> layer
        (true, true, true, true),
        (false, true, true, false),
        (true, false, true, false),
        (true, true, false, false),
        (false, false, false, false),
    ])
    func aLayerNeedsAllThree(mode: Bool, source: Bool, playing: Bool, expected: Bool) {
        #expect(
            PlayerVideoSlot.showsLayer(
                modeShowsVideo: mode,
                songHasSource: source,
                isPlayingThisSong: playing
            ) == expected
        )
    }
}

@MainActor
struct MediaModeToggleTests {
    @Test func theIconIsTheDestination() {
        #expect(MediaModeToggle.icon(isShowingVideo: false) == .video)
        #expect(MediaModeToggle.icon(isShowingVideo: true) == .headphones)
    }

    @Test func theTitleNamesTheDestination() {
        #expect(MediaModeToggle.title(isShowingVideo: false) == "Switch to video")
        #expect(MediaModeToggle.title(isShowingVideo: true) == "Switch to audio")
    }

    @Test func bothIconsResolveToASymbol() {
        #expect(IconToken.video.systemName == "video.fill")
        #expect(IconToken.headphones.systemName == "headphones")
    }
}
