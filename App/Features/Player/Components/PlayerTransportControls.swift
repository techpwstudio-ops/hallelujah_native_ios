import SwiftUI

/// T35 — ports `PlayerControls`' transport row (`audio_player_screen.dart`):
/// shuffle / previous / big center play-pause / next / repeat. Both toggle
/// buttons reuse the SAME glyph for their "off" and "on-but-not-distinct"
/// states, tinted differently, exactly matching Dart's own
/// `ShuffleWidget`/`LoopModeWidget` (grey when off, white when on) rather
/// than swapping icons: `IconToken.repeatAll`'s "repeat" glyph covers both
/// `.off` and `.all`; `.repeatOne`'s SF Symbol (`repeat.1`) already bakes in
/// the small "1" Dart draws as a separate badge overlay
/// (`loop_mode_widget.dart:38-58`), so no custom badge view is needed here.
struct PlayerTransportControls: View {
    @Environment(\.appTheme) private var theme
    let engine: AudioEngine
    let queueController: QueueController

    private static let playPauseDiameter: CGFloat = 58
    private static let sideGlyphSize: CGFloat = 22
    private static let toggleGlyphSize: CGFloat = 18
    private static let playGlyphSize: CGFloat = 26

    private var isPlaying: Bool { engine.status == .playing }

    var body: some View {
        HStack(spacing: Spacing.xl) {
            shuffleButton
            transportButton(.previous, size: Self.sideGlyphSize) {
                Task { await queueController.skipToPrevious() }
            }
            playPauseButton
            transportButton(.next, size: Self.sideGlyphSize) {
                Task { await queueController.skipToNext() }
            }
            repeatButton
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ icon: IconToken, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            theme.icon(icon)
                .font(.system(size: size))
                .foregroundStyle(theme.color(.textPrimary))
        }
        .buttonStyle(.plain)
    }

    private var shuffleButton: some View {
        Button {
            Task { await queueController.toggleShuffle() }
        } label: {
            theme.icon(.shuffle)
                .font(.system(size: Self.toggleGlyphSize))
                .foregroundStyle(queueController.isShuffled ? theme.color(.textPrimary) : theme.color(.textSecondary))
        }
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
        Button {
            queueController.cycleRepeatMode()
        } label: {
            theme.icon(queueController.repeatMode == .one ? .repeatOne : .repeatAll)
                .font(.system(size: Self.toggleGlyphSize))
                .foregroundStyle(queueController.repeatMode == .off ? theme.color(.textSecondary) : theme.color(.textPrimary))
        }
        .buttonStyle(.plain)
    }

    /// `PlayPauseIconFilled`: filled background circle (not the mini
    /// player's stroke-only ring), "white bg, dark icon" mapped to
    /// `textPrimary`/`backgroundPrimary` rather than literal
    /// black/white so it still reads correctly in both themes.
    private var playPauseButton: some View {
        Button {
            if isPlaying { engine.pause() } else { engine.resume() }
        } label: {
            ZStack {
                Circle().fill(theme.color(.textPrimary))
                theme.icon(isPlaying ? .pause : .play)
                    .font(.system(size: Self.playGlyphSize))
                    .foregroundStyle(theme.color(.backgroundPrimary))
            }
            .frame(width: Self.playPauseDiameter, height: Self.playPauseDiameter)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}
