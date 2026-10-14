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
struct PlayerTransportControls: View {
    let engine: AudioEngine
    let queueController: QueueController

    private var isPlaying: Bool { engine.status == .playing }
    private var isLoading: Bool { engine.status == .loading }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            shuffleButton
            Spacer(minLength: 0)
            seekButton(systemName: "backward.end.fill") {
                Task { await queueController.skipToPrevious() }
            }
            Spacer(minLength: 0)
            playPauseButton
            Spacer(minLength: 0)
            seekButton(systemName: "forward.end.fill") {
                Task { await queueController.skipToNext() }
            }
            Spacer(minLength: 0)
            loopButton
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleBackground<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(
                width: PlayerStyle.toggleGlyphSize + PlayerStyle.controlGlyphPadding * 2,
                height: PlayerStyle.toggleGlyphSize + PlayerStyle.controlGlyphPadding * 2
            )
            .background(PlayerStyle.whiteAlpha(PlayerStyle.shadowOpacity), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .contentShape(Rectangle())
    }

    private var shuffleButton: some View {
        Button {
            Task { await queueController.toggleShuffle() }
        } label: {
            toggleBackground {
                Image(systemName: "shuffle")
                    .font(.system(size: PlayerStyle.toggleGlyphSize * 0.8))
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
                    Image(systemName: "repeat")
                        .font(.system(size: PlayerStyle.toggleGlyphSize * 0.8))
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
