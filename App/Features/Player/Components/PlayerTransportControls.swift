import SwiftUI

/// Ports `PlayerControls` (`lib/widgets/player/player_controls.dart`):
/// `MainAxisAlignment.spaceAround` row of shuffle / previous / 58pt white
/// play-pause disc / next / loop. Shuffle and loop sit in a 48pt circle
/// filled `white @ 6%` (`MyContainer(background: white.withOpacity(0.06),
/// radius: 32)` around a 24pt glyph with 12pt padding), grey when off and
/// white when on; loop-one adds the 13pt white "1" badge
/// (`loop_mode_widget.dart`). Previous/next are 22pt glyphs with 12pt padding
/// that shrink to 0.75 while pressed (`_SeekButton`). Never disabled.
///
/// The Flutter glyphs are bundled SVGs (`arrow_left.svg`, `arrow_right.svg`,
/// `shuffle.svg`, `loop.svg`); until those are added to the asset catalog the
/// closest SF Symbols stand in for them.
///
/// For an episode the previous / next buttons become "back 10 seconds" and
/// "forward 10 seconds" (`gobackward.10` / `goforward.10`), which move the
/// playhead instead of the queue. Music keeps previous / next.
struct PlayerTransportControls: View {
    let engine: AudioEngine
    let queueController: QueueController

    /// How far an episode's skip buttons move the playhead, in seconds.
    static let skipInterval: TimeInterval = 10

    private var isPlaying: Bool { engine.status == .playing }
    private var isLoading: Bool { engine.status == .loading }
    private var isEpisode: Bool { engine.currentSong?.isEpisode ?? false }

    /// Where a skip of `delta` seconds from `position` lands: never before the
    /// start, and never past `duration` when that is known (zero, negative or
    /// `nil` mean it is not).
    static func skipTarget(from position: TimeInterval, by delta: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        let target = max(position + delta, 0)
        guard let duration, duration.isFinite, duration > 0 else { return target }
        return min(target, duration)
    }

    var body: some View {
        GlassContainer(spacing: Spacing.sm) {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            shuffleButton
            Spacer(minLength: 0)
            if isEpisode {
                EpisodeSkipButton(engine: engine, direction: .back)
            } else {
                seekButton(systemName: "backward.end.fill") {
                    Task { await queueController.skipToPrevious() }
                }
            }
            Spacer(minLength: 0)
            playPauseButton
            Spacer(minLength: 0)
            if isEpisode {
                EpisodeSkipButton(engine: engine, direction: .forward)
            } else {
                seekButton(systemName: "forward.end.fill") {
                    Task { await queueController.skipToNext() }
                }
            }
            Spacer(minLength: 0)
            loopButton
            Spacer(minLength: 0)
        }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleBackground<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(
                width: PlayerStyle.toggleGlyphSize + PlayerStyle.controlGlyphPadding * 2,
                height: PlayerStyle.toggleGlyphSize + PlayerStyle.controlGlyphPadding * 2
            )
            .glassCircle(interactive: true)
            .contentShape(Circle())
    }

    private var shuffleButton: some View {
        Button {
            Task { await queueController.toggleShuffle() }
        } label: {
            toggleBackground {
                IconView(token: .shuffle, size: PlayerStyle.toggleGlyphSize * 0.8)
                    .foregroundStyle(queueController.isShuffled ? PlayerStyle.white : PlayerStyle.grey)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
    }

    private var loopButton: some View {
        let mode = queueController.repeatMode
        return Button {
            queueController.cycleRepeatMode()
        } label: {
            toggleBackground {
                ZStack {
                    IconView(token: .repeatAll, size: PlayerStyle.toggleGlyphSize * 0.8)
                        .foregroundStyle(mode == .off ? PlayerStyle.grey : PlayerStyle.white)
                    if mode == .one {
                        Text("1")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(PlayerStyle.black)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(PlayerStyle.white))
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .bottomTrailing
                            )
                            .padding(6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
    }

    private func seekButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: PlayerStyle.seekGlyphSize))
                .foregroundStyle(PlayerStyle.white)
                .padding(PlayerStyle.controlGlyphPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerPressScaleStyle())
    }

    private var playPauseButton: some View {
        Button {
            if isPlaying { engine.pause() } else { engine.resume() }
        } label: {
            PlayerPlayPauseDisc(isPlaying: isPlaying, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// An episode's "back 10 seconds" or "forward 10 seconds" button, on the full
/// player's transport row and on the full-screen lyrics page
/// (`EpisodeSkipButton` in `lib/widgets/player/player_controls.dart`).
/// `engine.seek` publishes the new position at once, so quick repeated taps add
/// up instead of each starting from the old position.
struct EpisodeSkipButton: View {
    enum Direction { case back, forward }

    let engine: AudioEngine
    let direction: Direction

    private var delta: TimeInterval {
        direction == .forward ? PlayerTransportControls.skipInterval : -PlayerTransportControls.skipInterval
    }

    private var label: LocalizedStringKey {
        direction == .forward ? "Forward 10 seconds" : "Rewind 10 seconds"
    }

    var body: some View {
        Button {
            let duration = engine.currentItemDuration ?? engine.currentSong.map { TimeInterval($0.duration ?? 0) }
            engine.seek(to: PlayerTransportControls.skipTarget(from: engine.currentPosition, by: delta, duration: duration))
            HapticFeedback.impact(.light).trigger()
        } label: {
            Image(systemName: direction == .forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: PlayerStyle.skipGlyphSize))
                .foregroundStyle(PlayerStyle.white)
                .padding(PlayerStyle.controlGlyphPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerPressScaleStyle())
        .accessibilityLabel(label)
    }
}
