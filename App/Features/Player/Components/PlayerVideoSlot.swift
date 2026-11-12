import SwiftUI

/// Everything the artwork pager needs to lay an episode's silent video over its cover.
struct PlayerVideoContext {
    let mode: PlayerVideoModeStore
    let source: PlayerVideoSource
    let clock: any AudioClock
    /// The episode the audio engine has loaded. A page of the pager shows video only for this one:
    /// the video follows the audio, so a page the listener has swiped to but the audio has not
    /// reached has no clock to follow.
    let playingSongId: String?
    /// The player is on screen and in front: the app is not in the background and no page is pushed
    /// over it. Sheets do not count, so the video keeps playing under one.
    let isVisible: Bool
    /// The video cannot be played. Called once per attempt.
    let onUnavailable: @MainActor () -> Void
    /// Video is locked behind a subscription for this listener (`PremiumFeature.videoMode`): no
    /// layer, whatever the mode says.
    var isLocked = false
    /// Opens the video full screen in landscape; `nil` draws no expand control.
    var onExpand: (@MainActor () -> Void)? = nil
}

/// One page's place for the silent video, over its cover: a layer when the listener has chosen
/// video, this episode has one, and the audio is playing this episode; nothing otherwise.
struct PlayerVideoSlot: View {
    let song: Song
    let context: PlayerVideoContext

    /// The three things that must all hold for a video to open. Any one turning false removes the
    /// layer, and that releases the player.
    static func showsLayer(modeShowsVideo: Bool, songHasSource: Bool, isPlayingThisSong: Bool) -> Bool {
        modeShowsVideo && songHasSource && isPlayingThisSong
    }

    var body: some View {
        if !context.isLocked, Self.showsLayer(
            modeShowsVideo: context.mode.showsVideo,
            songHasSource: song.hasVideo,
            isPlayingThisSong: context.playingSongId == song.id
        ) {
            layer
        }
    }

    @ViewBuilder
    private var layer: some View {
        if let url = context.source.url(for: song) {
            let source = context.source
            PlayerVideoLayer(
                songId: song.id,
                url: url,
                clock: context.clock,
                modeShowsVideo: context.mode.showsVideo,
                isVisible: context.isVisible,
                makeHeaders: { await source.headers() },
                onUnavailable: context.onUnavailable,
                onExpand: context.onExpand
            )
            // Another episode, or another file for the same one, is a new layer with a new controller.
            .id(PlayerVideoLayerKey(songId: song.id, url: url))
        } else {
            // A key that is there but cannot become a URL is a video that is not available.
            let onUnavailable = context.onUnavailable
            Color.clear.task { onUnavailable() }
        }
    }
}
