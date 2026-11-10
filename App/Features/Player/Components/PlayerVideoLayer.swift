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
    let isVisible: Bool
    let makeHeaders: @Sendable () async -> [String: String]
    let onUnavailable: @MainActor () -> Void

    @State private var controller: PlayerVideoController
    @State private var playback: AVVideoPlayback?

    init(
        songId: String,
        url: URL,
        clock: any AudioClock,
        isVisible: Bool,
        makeHeaders: @escaping @Sendable () async -> [String: String],
        onUnavailable: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.isVisible = isVisible
        self.makeHeaders = makeHeaders
        self.onUnavailable = onUnavailable
        // SwiftUI keeps the first controller it is given and drops the rest.
        _controller = State(initialValue: PlayerVideoController(clock: clock, songId: songId))
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
            try? await Task.sleep(for: .milliseconds(VideoSync.reconcileIntervalMs))
            guard !Task.isCancelled else { return }
            controller.tick()
            if controller.hasFailed {
                onUnavailable()
                return
            }
        }
    }
}
