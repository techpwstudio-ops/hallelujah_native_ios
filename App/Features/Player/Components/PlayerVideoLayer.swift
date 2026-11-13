import AVFoundation
import SwiftUI

/// The handoff between the artwork pager's layers, which play real `AVPlayer`s.
typealias PlayerVideoLayerHandoff = PlayerVideoHandoff<AVVideoPlayback>

/// One episode's silent video, drawn over its cover. The slot gives it `.id(song.id)`, so another
/// episode is a new layer. Another quality is the same layer: it opens the new file behind the
/// picture on screen and swaps the two once the new one is in step (`PlayerVideoStage`).
struct PlayerVideoLayer: View {
    /// The file for the quality the listener picked.
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
    /// Where this layer leaves its player when it goes away, and where it looks for one to take over
    /// when it starts. `nil` (the full-screen view) opens and releases its own, as before.
    var handoff: PlayerVideoLayerHandoff? = nil

    private let songId: String
    private let clock: any AudioClock

    @State private var stage: PlayerVideoStage<AVVideoPlayback>

    init(
        songId: String,
        url: URL,
        clock: any AudioClock,
        modeShowsVideo: Bool,
        isVisible: Bool,
        makeHeaders: @escaping @Sendable () async -> [String: String],
        onUnavailable: @escaping @MainActor () -> Void,
        onExpand: (@MainActor () -> Void)? = nil,
        qualityMenu: PlayerVideoQualityMenu.Model? = nil,
        handoff: PlayerVideoLayerHandoff? = nil
    ) {
        self.url = url
        self.modeShowsVideo = modeShowsVideo
        self.isVisible = isVisible
        self.makeHeaders = makeHeaders
        self.onUnavailable = onUnavailable
        self.onExpand = onExpand
        self.qualityMenu = qualityMenu
        self.handoff = handoff
        self.songId = songId
        self.clock = clock
        // SwiftUI keeps the first stage it is given and drops the rest. When another layer has left
        // a player for this episode, this one starts from it, so its first frame already draws the
        // picture instead of the cover, even when it wants another quality.
        _stage = State(initialValue: PlayerVideoStage(wanted: url, showing: handoff?.peek(songId)))
    }

    /// Whether the loading spinner is up: the listener has asked for video, the picture is not on
    /// screen yet, and the video has not given up. It is up from the tap, through opening the file
    /// and getting in step with the audio, until the picture has faded in. A quality change keeps
    /// the old picture up meanwhile, so it shows none.
    static func showsSpinner(modeShowsVideo: Bool, isPictureShown: Bool, hasGivenUp: Bool) -> Bool {
        modeShowsVideo && !isPictureShown && !hasGivenUp
    }

    /// What is drawn, bottom to top: the picture on screen, then the new quality fading in over it.
    private var players: [PlayerVideoStage<AVVideoPlayback>.Player] {
        [stage.current, stage.incoming].compactMap { $0 }
    }

    var body: some View {
        GeometryReader { box in
            ZStack {
                // Keyed by player, so the picture on screen keeps its surface when the swap makes it
                // the bottom one, and never redraws from black.
                ForEach(players) { player in
                    let controller = player.controller
                    if controller.videoSize != .zero {
                        VideoSurface(player: player.playback.player, gravity: gravity(controller.videoSize, in: box.size))
                            .opacity(controller.isShown ? 1 : 0)
                            .animation(.easeOut(duration: MotionDuration.crossfade), value: controller.isShown)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isVisible) { await run() }
        // The task reads the stage, not `url`, which it captured when it started.
        .onChange(of: url) { _, newValue in stage.want(newValue) }
        // After the modifiers above, which keep the picture out of touch and VoiceOver: the
        // spinner brings its own.
        .overlay {
            PlayerVideoLoadingIndicator(
                isVisible: Self.showsSpinner(
                    modeShowsVideo: modeShowsVideo,
                    isPictureShown: stage.isPictureShown,
                    hasGivenUp: stage.hasFailed
                )
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if let onExpand, stage.isPictureShown {
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
            if let qualityMenu, stage.isPictureShown {
                PlayerVideoQualityMenu(model: qualityMenu)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: MotionDuration.crossfade), value: stage.isPictureShown)
    }

    private func gravity(_ size: CGSize, in box: CGSize) -> AVLayerVideoGravity {
        let fit = VideoSync.fit(
            videoAspect: size.height > 0 ? size.width / size.height : 0,
            boxAspect: box.height > 0 ? box.width / box.height : 0
        )
        return fit == .cover ? .resizeAspectFill : .resizeAspect
    }

    private func run() async {
        // The stage itself, not `self.stage`: the defer below may run after the view has gone.
        let stage = self.stage
        guard isVisible else {
            // Out of sight: nothing is kept. Coming back opens the file again.
            handoff?.discard(songId)
            stage.clear()
            return
        }
        let owner = PlayerVideoLayerHandoff.Owner()
        // The player another layer (or this one's last run) left for this episode, if any. Without
        // one, whatever the stage still points at has been released.
        if let handoff { stage.show(handoff.claim(songId, by: owner)) }
        defer {  // runs on cancel: hidden, or off the tree
            // A file still opening for a new quality is this layer's alone.
            if let incoming = stage.incoming { stage.drop(incoming) }
            if let shown = stage.current {
                if let handoff {
                    // Kept for a moment for a new layer of the same episode (the pager builds the
                    // page afresh when shuffle moves it); released at once if the video failed.
                    handoff.letGo(songId, by: owner, keep: !shown.controller.hasFailed)
                } else {
                    shown.controller.release()
                }
            }
        }
        // A first look at once, then quick while the listener waits for a picture or a switch is
        // under way, so either happens the moment it can.
        var step = VideoSync.reconcileIntervalMs
        while !Task.isCancelled {
            if stage.needsOpening {
                guard await open(on: stage, as: owner) else { return }
            }
            switch stage.tick(stepMs: step) {
            case .switched(let player):
                handoff?.hold(player, for: songId, by: owner)
            case .failed:
                onUnavailable()
                return
            case nil:
                break
            }
            step = stage.isSettled && stage.isPictureShown
                ? VideoSync.reconcileIntervalMs
                : VideoSync.fastReconcileIntervalMs
            try? await Task.sleep(for: .milliseconds(step))
            // Stop when cancelled, or when a new layer has taken the player over.
            guard !Task.isCancelled, owns(as: owner) else { return }
        }
    }

    /// Opens the file the listener wants and puts it on stage. `false` when the task was cancelled
    /// or a new layer took over meanwhile.
    private func open(on stage: PlayerVideoStage<AVVideoPlayback>, as owner: PlayerVideoLayerHandoff.Owner) async -> Bool {
        let url = stage.wanted
        let headers = await makeHeaders()  // the token is fetched here; cancellation-safe
        guard !Task.isCancelled, owns(as: owner) else { return false }
        // The layer this one replaces may have let go while the token was fetched.
        if stage.current == nil, let handoff { stage.show(handoff.claim(songId, by: owner)) }
        // The listener may have picked again meanwhile, or the player taken over already plays it.
        guard stage.wanted == url, stage.needsOpening else { return true }
        let playback = AVVideoPlayback(url: url, headers: headers)
        let controller = PlayerVideoController(clock: clock, songId: songId)
        controller.attach(playback)
        let player = PlayerVideoLayerHandoff.Held(controller: controller, playback: playback, url: url)
        if stage.open(player) == .current {
            handoff?.hold(player, for: songId, by: owner)
        }
        return true
    }

    /// Whether this layer still runs the episode's video: no other layer has taken it over. Not
    /// "holds a player", since nothing is held until the first file opens.
    private func owns(as owner: PlayerVideoLayerHandoff.Owner) -> Bool {
        !(handoff?.isTakenOver(songId, from: owner) ?? false)
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
