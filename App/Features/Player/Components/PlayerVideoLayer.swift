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
    /// Opens the video full screen in landscape. When set, the expand button sits in the picture's
    /// bottom trailing corner and a tap on the picture does the same, both only while the picture
    /// is up. `nil` (the full-screen view itself) draws neither.
    var onExpand: (@MainActor () -> Void)? = nil
    /// The quality button, in the picture's top trailing corner while the picture is up. `nil` draws
    /// none; it also draws none for an episode with fewer than two qualities to choose between.
    var qualityMenu: PlayerVideoQualityMenu.Model? = nil

    @State private var controller: PlayerVideoController
    @State private var playback: AVVideoPlayback?

    init(
        songId: String,
        url: URL,
        clock: any AudioClock,
        modeShowsVideo: Bool,
        isVisible: Bool,
        makeHeaders: @escaping @Sendable () async -> [String: String],
        onUnavailable: @escaping @MainActor () -> Void,
        onExpand: (@MainActor () -> Void)? = nil,
        qualityMenu: PlayerVideoQualityMenu.Model? = nil
    ) {
        self.url = url
        self.modeShowsVideo = modeShowsVideo
        self.isVisible = isVisible
        self.makeHeaders = makeHeaders
        self.onUnavailable = onUnavailable
        self.onExpand = onExpand
        self.qualityMenu = qualityMenu
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
        .overlay(alignment: .bottomTrailing) {
            if let onExpand, controller.isShown {
                ZStack(alignment: .bottomTrailing) {
                    // A tap anywhere on the picture opens it full screen too.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onExpand() }
                        .accessibilityHidden(true)
                    PlayerVideoExpandButton(action: onExpand)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let qualityMenu, controller.isShown {
                PlayerVideoQualityMenu(model: qualityMenu)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: MotionDuration.crossfade), value: controller.isShown)
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

/// The quality button on the picture: a gear that opens a menu of this episode's qualities. Only
/// what the episode has and this device can play is listed, and the current choice is ticked.
/// Picking one writes the setting, which reloads just the picture (the audio never stops).
struct PlayerVideoQualityMenu: View {
    /// What the menu reads and writes. A value, so a layer can be handed one without owning the store.
    struct Model {
        let store: VideoQualityStore
        let song: Song
    }

    let model: Model

    /// The entries: Auto first, then each quality the episode offers. Empty when there is nothing to
    /// choose between.
    static func entries(options: [VideoQuality]) -> [VideoQuality] {
        options.count >= 2 ? [.auto] + options : []
    }

    var body: some View {
        let entries = Self.entries(options: model.store.options(for: model.song))
        if !entries.isEmpty {
            Menu {
                Picker(
                    String(localized: "Video Quality"),
                    selection: Binding(
                        get: { model.store.preference },
                        set: { model.store.setPreference($0) }
                    )
                ) {
                    ForEach(entries, id: \.self) { quality in
                        Text(title(for: quality)).tag(quality)
                    }
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: PlayerStyle.videoExpandGlyphSize, weight: .semibold))
                    .foregroundStyle(PlayerStyle.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .frame(width: PlayerStyle.queueRowBox, height: PlayerStyle.queueRowBox)
                    .contentShape(Rectangle())
            }
            .padding(Dimens.spacing6)
            .accessibilityLabel(String(localized: "Video Quality"))
        }
    }

    /// "Auto" says what it is playing right now, so the listener can see what Auto picked.
    private func title(for quality: VideoQuality) -> String {
        guard quality == .auto, let current = model.store.choice(for: model.song)?.quality,
              model.store.preference == .auto
        else { return quality.displayName }
        return String(localized: "Auto (\(current.displayName))")
    }
}

/// The expand control in the picture's corner: Spotify's two outward diagonal arrows, white with a
/// soft shadow so it reads over any frame, in a 44 pt box.
struct PlayerVideoExpandButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: PlayerStyle.videoExpandGlyphSize, weight: .semibold))
                .foregroundStyle(PlayerStyle.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .frame(width: PlayerStyle.queueRowBox, height: PlayerStyle.queueRowBox)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(Dimens.spacing6)
        .accessibilityLabel(String(localized: "Full screen"))
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
