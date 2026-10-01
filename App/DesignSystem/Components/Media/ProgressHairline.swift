import SwiftUI

/// Passive, non-interactive playback progress line — native port of
/// `MyLinerProgressIndicator` (`song_progress_bar.dart`'s `preview: true`
/// branch): `minHeight: 2`, `color: whiteColor`,
/// `backgroundColor: ColorTheme.fillColor.withOpacity(0.8)`.
///
/// Named to match the roadmap's own wording for where this is used — T34
/// (Mini player) calls this exact element "progress hairline" — rather than
/// the more literal `MyLinerProgressIndicator` port name. `SeekBar` (this
/// file's sibling) is the other of `SongProgressBar`'s two branches: the
/// full, draggable control for the full player screen. Same
/// `textInverse`-substitution reasoning as `SeekBar` for Dart's hardcoded
/// white-on-dark palette.
struct ProgressHairline: View {
    var progress: Double // 0...1

    @Environment(\.appTheme) private var theme

    private static let height: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.color(.textInverse).opacity(0.24))
                Capsule(style: .continuous)
                    .fill(theme.color(.textInverse))
                    .frame(width: proxy.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .frame(height: Self.height)
    }
}
