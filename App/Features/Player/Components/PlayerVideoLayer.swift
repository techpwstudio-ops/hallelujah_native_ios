import AVFoundation
import SwiftUI

/// One episode's silent video, drawn over its cover. The slot gives it
/// `.id(PlayerVideoLayerKey(songId:url:))`, so another episode, or another file for the same
/// episode, is a new layer with a new controller.
struct PlayerVideoLayerKey: Hashable {
    let songId: String
    let url: URL
}

struct PlayerVideoLayer: View {
    let url: URL
    /// The listener has chosen video. The slot only builds a layer while this holds; it is passed
    /// down so the spinner's rule reads the same three facts the listener would.
    let modeShowsVideo: Bool
    let isVisible: Bool
    let makeHeaders: @Sendable () async -> [String: String]
    let onUnavailable: @MainActor () -> Void

    @State private var controller: PlayerVideoController
    @State private var playback: AVVideoPlayback?

    init(
        songId: String,
        url: URL,
        clock: any AudioClock,
        modeShowsVideo: Bool,
        isVisible: Bool,
        makeHeaders: @escaping @Sendable () async -> [String: String],
        onUnavailable: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.modeShowsVideo = modeShowsVideo
        self.isVisible = isVisible
        self.makeHeaders = makeHeaders
        self.onUnavailable = onUnavailable
        // SwiftUI keeps the first controller it is given and drops the rest.
        _controller = State(initialValue: PlayerVideoController(clock: clock, songId: songId))
    }

    /// Whether the loading spinner is up: the listener has asked for video, the picture is not on
    /// screen yet, and the video has not given up. It is up from the tap, through opening the file
    /// and getting in step with the audio, until the picture has faded in.
    static func showsSpinner(modeShowsVideo: Bool, isPictureShown: Bool, hasGivenUp: Bool) -> Bool {
        modeShowsVideo && !isPictureShown && !hasGivenUp
    }

    var body: some View {
        GeometryReader { box in
            if let playback, controller.videoSize != .zero {
                VideoSurface(player: playback.player, gravity: gravity(in: box.size))
                    .opacity(controller.isShown ? 1 : 0)
                    .animation(.easeOut(duration: MotionDuration.crossfade), value: controller.isShown)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isVisible) { await run() }
        // After the two modifiers above, which keep the picture out of touch and VoiceOver: the
        // spinner brings its own.
        .overlay {
            PlayerVideoLoadingIndicator(
                isVisible: Self.showsSpinner(
                    modeShowsVideo: modeShowsVideo,
                    isPictureShown: controller.isShown,
                    hasGivenUp: controller.hasFailed
                )
            )
        }
    }

    private func gravity(in box: CGSize) -> AVLayerVideoGravity {
        let size = controller.videoSize
        let fit = VideoSync.fit(
            videoAspect: size.height > 0 ? size.width / size.height : 0,
            boxAspect: box.height > 0 ? box.width / box.height : 0
        )
        return fit == .cover ? .resizeAspectFill : .resizeAspect
    }

    private func run() async {
        guard isVisible else { return }
        let headers = await makeHeaders()  // the token is fetched here; cancellation-safe
        guard !Task.isCancelled else { return }
        let opened = AVVideoPlayback(url: url, headers: headers)
        playback = opened
        controller.attach(opened)
        defer {  // runs on cancel: hidden, or off the tree
            controller.release()
            playback = nil
        }
        controller.tick()  // a first look at once; a no-op until the item is ready
        while !Task.isCancelled {
            // Quick while the listener waits for the picture, so it comes up the moment it is ready.
            let step = controller.isShown ? VideoSync.reconcileIntervalMs : VideoSync.fastReconcileIntervalMs
            try? await Task.sleep(for: .milliseconds(step))
            guard !Task.isCancelled else { return }
            controller.tick(stepMs: step)
            if controller.hasFailed {
                onUnavailable()
                return
            }
        }
    }
}

/// A spinner centred over the artwork while the silent video comes up, on a small dark square so it
/// shows over a light cover. It appears only once the wait has lasted `VideoSync.spinnerDelayMs`,
/// so a quick switch shows none. It fades in and out, takes no touches and no space.
struct PlayerVideoLoadingIndicator: View {
    let isVisible: Bool

    /// False until the first frame, so a spinner that is up from the start fades in, not pops in.
    @State private var hasAppeared = false
    /// The wait has lasted long enough to be worth a spinner.
    @State private var delayPassed = false

    var body: some View {
        ZStack {
            if isVisible && delayPassed {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(PlayerStyle.white)
                    .scaleEffect(PlayerStyle.loadingSpinnerScale)
                    .frame(width: PlayerStyle.loadingBackdropSize, height: PlayerStyle.loadingBackdropSize)
                    .background(
                        PlayerStyle.loadingBackdrop,
                        in: RoundedRectangle(cornerRadius: PlayerStyle.loadingBackdropRadius, style: .continuous)
                    )
                    .opacity(hasAppeared ? 1 : 0)
                    .transition(.opacity)
                    .accessibilityLabel(String(localized: "Loading…"))
            }
        }
        .animation(.easeOut(duration: MotionDuration.crossfade), value: isVisible)
        .animation(.easeOut(duration: MotionDuration.crossfade), value: hasAppeared)
        .animation(.easeOut(duration: MotionDuration.crossfade), value: delayPassed)
        .allowsHitTesting(false)
        .onAppear { hasAppeared = true }
        .task(id: isVisible) {
            delayPassed = false
            guard isVisible else { return }
            try? await Task.sleep(for: .milliseconds(VideoSync.spinnerDelayMs))
            guard !Task.isCancelled else { return }
            delayPassed = true
        }
    }
}

#Preview("Loading indicator over a light cover") {
    ZStack {
        Color(white: 0.9)
        PlayerVideoLoadingIndicator(isVisible: true)
    }
    .frame(height: 220)
}
