import SwiftUI

/// Literal colours and metrics the Flutter player surfaces hard-code
/// (`ColorTheme.*`, `Colors.white.withValues(alpha:)`, per-widget sizes).
/// D12 requires exact parity, so they live here — scoped to the player
/// feature — rather than in the shared token files. The Flutter app is
/// dark-only, so these are intentionally fixed values, not theme-adaptive.
enum PlayerStyle {
    // MARK: Colours (`lib/theme/colors.dart`)

    static let white = Color.white
    static let black = Color.black
    static func whiteAlpha(_ opacity: Double) -> Color { Color.white.opacity(opacity) }
    /// `ColorTheme.fillColor` (0xFF1D1D1D).
    static let fill = Color(red: 29.0 / 255, green: 29.0 / 255, blue: 29.0 / 255)
    /// `ColorTheme.darkSurface` (0xFF1C1C1C).
    static let darkSurface = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 28.0 / 255)
    /// `ColorTheme.bottomSheetBgColor` (0xFF111111).
    static let bottomSheetBackground = Color(red: 17.0 / 255, green: 17.0 / 255, blue: 17.0 / 255)
    /// Sleep-timer accent (`_kAccent`, 0xFF9B8FFF).
    static let sleepAccent = Color(red: 155.0 / 255, green: 143.0 / 255, blue: 255.0 / 255)
    /// `Vx.yellow500` — the active row title in `BaseMediaListTile`.
    static let activeYellow = Color(red: 1.0, green: 235.0 / 255, blue: 59.0 / 255)
    /// `Colors.redAccent` (0xFFFF5252).
    static let redAccent = Color(red: 1.0, green: 82.0 / 255, blue: 82.0 / 255)
    /// `Colors.grey` (0xFF9E9E9E) — inactive shuffle / loop glyph.
    static let grey = Color(red: 158.0 / 255, green: 158.0 / 255, blue: 158.0 / 255)
    /// `Colors.grey.shade400` / `shade600` (ad Skip chip).
    static let greySubtle = Color(red: 189.0 / 255, green: 189.0 / 255, blue: 189.0 / 255)
    static let greyMuted = Color(red: 117.0 / 255, green: 117.0 / 255, blue: 117.0 / 255)
    /// `shadowOpacity` (`lib/theme/values.dart`).
    static let shadowOpacity: Double = 0.06

    // MARK: Typography (`AppTextStyles` + per-call-site overrides)

    static let titleMediumBold = TypographyToken(size: 16, weight: .bold, lineHeightMultiple: 1.4)
    static let titleMediumSemibold = TypographyToken(size: 16, weight: .semibold, lineHeightMultiple: 1.4)
    static let lyricsLine = TypographyToken(size: 16, weight: .bold, lineHeightMultiple: 1.4)
    static let timeLabel = TypographyToken(size: 12, weight: .regular, lineHeightMultiple: 1.5)
    static let playingFromLabel = TypographyToken(size: 9, weight: .semibold, lineHeightMultiple: 1.2, tracking: 0.9)

    // MARK: Layout (`audio_player_screen.dart` / `player_controls.dart`)

    static let pageSidePadding: CGFloat = 20
    static let playButtonDiameter: CGFloat = 58
    static let playGlyphSize: CGFloat = 32
    static let seekGlyphSize: CGFloat = 22
    static let controlGlyphPadding: CGFloat = 12
    static let toggleGlyphSize: CGFloat = 24
    static let seekBarHeight: CGFloat = 6
    static let thumbRadius: CGFloat = 6
    static let toolbarHeight: CGFloat = 56
}

/// Press feedback of `_SeekButton`: `AnimatedScale` to 0.75, 100 ms easeOut.
struct PlayerPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// `PlayPauseIconFilled`'s disc: white circle, dark `play_arrow_rounded` /
/// `pause_rounded`, glyph swap scales over 200 ms easeInOut, dimmed to 40%
/// while the track is loading (`icons.dart`).
struct PlayerPlayPauseDisc: View {
    let isPlaying: Bool
    let isLoading: Bool
    var diameter: CGFloat = PlayerStyle.playButtonDiameter
    var glyphSize: CGFloat = PlayerStyle.playGlyphSize

    var body: some View {
        ZStack {
            Circle().fill(PlayerStyle.white)
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: glyphSize * 0.8))
                .foregroundStyle(PlayerStyle.black)
                // Swap the glyph in place. The old `.id` + `.transition(.scale)`
                // removed one image before inserting the other, leaving an
                // empty white disc for a frame on every song change.
                .contentTransition(.symbolEffect(.replace))
                .opacity(isLoading ? 0.4 : 1)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}
