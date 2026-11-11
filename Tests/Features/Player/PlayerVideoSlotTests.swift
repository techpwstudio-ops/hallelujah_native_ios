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
        #expect(MediaModeToggle.systemName(isShowingVideo: false) == "video")
        #expect(MediaModeToggle.systemName(isShowingVideo: true) == "headphones")
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

@MainActor
struct PlayerVideoLoadingTests {
    @Test(arguments: [
        // video mode on, picture not shown, not given up -> spinner
        (true, false, false, true),
        // the picture is on screen -> no spinner
        (true, true, false, false),
        // the listener is back on the audio -> no spinner
        (false, false, false, false),
        (false, true, false, false),
        // the video gave up -> no spinner
        (true, false, true, false),
        (true, true, true, false),
        (false, false, true, false),
    ])
    func theSpinnerIsUpWhileVideoIsAskedForAndNotYetShown(
        mode: Bool,
        shown: Bool,
        gaveUp: Bool,
        expected: Bool
    ) {
        #expect(
            PlayerVideoLayer.showsSpinner(
                modeShowsVideo: mode,
                isPictureShown: shown,
                hasGivenUp: gaveUp
            ) == expected
        )
    }
}
