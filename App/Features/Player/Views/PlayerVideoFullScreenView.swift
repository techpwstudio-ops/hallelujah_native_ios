import SwiftUI

/// An episode's silent video full screen, turned to landscape. Opened from the expand button (or a
/// tap) on the video in the full player.
///
/// It runs its own `PlayerVideoLayer`, following the same audio clock, so the picture stays in step
/// with what is heard. The player underneath releases its own video while this is up, so there is
/// only ever one video player open; the picture takes a moment to come up on entering and on
/// leaving for that reason.
///
/// A tap shows or hides the controls: collapse, and play / pause for the audio. They hide on their
/// own after a few seconds of playing.
struct PlayerVideoFullScreenView: View {
    let song: Song
    let engine: AudioEngine
    let source: PlayerVideoSource
    /// Read here, not handed down as a URL, so a quality picked from the menu below reloads this
    /// picture too.
    let quality: VideoQualityStore
    let onUnavailable: @MainActor () -> Void
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var controlsVisible = true

    /// How long the controls stay up while the audio plays.
    private static let controlsHideDelay: Duration = .seconds(3)

    private var isPlaying: Bool { engine.status == .playing }

    /// The file for the current choice; `nil` while Auto waits for its first reading of the connection.
    private var url: URL? {
        quality.choice(for: song).flatMap { source.url(for: song, choice: $0) }
    }

    var body: some View {
        ZStack {
            PlayerStyle.black.ignoresSafeArea()

            if let url {
                PlayerVideoLayer(
                    songId: song.id,
                    url: url,
                    clock: EngineAudioClock(engine: engine),
                    modeShowsVideo: true,
                    isVisible: scenePhase != .background,
                    makeHeaders: { [source] in await source.headers() },
                    onUnavailable: onUnavailable
                )
                // Another file for the same episode (a new quality) is a new layer, as in the slot.
                .id(PlayerVideoLayerKey(songId: song.id, url: url))
                .ignoresSafeArea()
            } else if quality.isReady {
                // A key that is there but cannot become a URL.
                Color.clear.task { onUnavailable() }
            }

            // Everything below the controls catches the tap that toggles them.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { controlsVisible.toggle() }
                .accessibilityHidden(true)

            if controlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: MotionDuration.crossfade), value: controlsVisible)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { OrientationLock.landscape() }
        .onDisappear { OrientationLock.portrait() }
        // Hide the controls a moment after they come up, while the audio plays.
        .task(id: "\(controlsVisible)|\(isPlaying)") {
            guard controlsVisible, isPlaying else { return }
            try? await Task.sleep(for: Self.controlsHideDelay)
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
        // Another track, or the audio stopped: nothing left to show here.
        .onChange(of: engine.currentSong?.id) { _, newValue in
            if newValue != song.id { onClose() }
        }
    }

    private var controls: some View {
        ZStack {
            // A light scrim so the white controls read over a bright frame.
            Color.black.opacity(0.35).ignoresSafeArea()
                .allowsHitTesting(false)

            Button {
                if isPlaying { engine.pause() } else { engine.resume() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: PlayerStyle.playGlyphSize, weight: .semibold))
                    .foregroundStyle(PlayerStyle.white)
                    .frame(width: PlayerStyle.playButtonDiameter, height: PlayerStyle.playButtonDiameter)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            VStack {
                HStack(alignment: .top) {
                    Text(song.title ?? "")
                        .typography(PlayerStyle.titleMediumSemibold)
                        .foregroundStyle(PlayerStyle.white)
                        .lineLimit(1)
                    Spacer(minLength: Dimens.spacing16)
                    PlayerVideoQualityMenu(model: .init(store: quality, song: song))
                }
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: PlayerStyle.videoExpandGlyphSize, weight: .semibold))
                            .foregroundStyle(PlayerStyle.white)
                            .frame(width: PlayerStyle.queueRowBox, height: PlayerStyle.queueRowBox)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Exit full screen"))
                }
            }
            .padding(Dimens.spacing16)
        }
    }
}
