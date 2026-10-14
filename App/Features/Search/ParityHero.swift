import SwiftUI

/// Hero image used by `GenreSongs`, `UserPlaylistSongs` and the creator page
/// (`SliverAppBar` `flexibleSpace` = `LoadImage` + a scrim). `aspect` is
/// width / height of the image *including* the status-bar area it extends
/// under (Dart: `expandedHeight = width * 3/4 - topInset`, i.e. total height
/// `width * 3/4`; the user playlist uses `width`).
struct ParityHeroImage: View {
    let url: URL?
    /// width / height.
    var aspect: CGFloat = 4.0 / 3.0
    var stops: [Gradient.Stop] = ParityHeroImage.defaultStops

    /// `GradiantDecoratedBox`: black @ 0.7 -> clear (0.32) -> clear (0.68) -> black @ 0.7.
    static let defaultStops: [Gradient.Stop] = [
        .init(color: Color.black.opacity(0.7), location: 0.0),
        .init(color: Color.clear, location: 0.32),
        .init(color: Color.clear, location: 0.68),
        .init(color: Color.black.opacity(0.7), location: 1.0),
    ]

    /// `UserPlaylistSongs`' deeper scrim.
    static let playlistStops: [Gradient.Stop] = [
        .init(color: Color.black.opacity(0), location: 0.0),
        .init(color: Color.black.opacity(0.2), location: 0.35),
        .init(color: Color.black.opacity(0.733), location: 0.7),
        .init(color: Color.black, location: 1.0),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ArtworkView(
                    url: url,
                    width: proxy.size.width,
                    height: proxy.size.height,
                    cornerRadius: 0,
                    contentMode: .fill
                )
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

/// `Theme.textTheme.headlineSmall` (Material default, not overridden by
/// `AppTextStyles.textTheme`): 24pt regular, 1.33 line height.
enum ParityHeroText {
    static let headlineSmall = TypographyToken(size: 24, weight: .regular, lineHeightMultiple: 1.33)
    static let labelMedium = Typography.labelMedium
    static let labelSmall = Typography.labelSmall
}

/// `ShuffleWidget` (`lib/widgets/player/shuffled_widget.dart`): 24pt shuffle
/// glyph (grey off / white on) padded 12 inside a white 6% circle.
struct ParityShuffleButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "shuffle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isOn ? Color.white : ParityColor.grey)
                .frame(width: 24, height: 24)
                .padding(12)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
    }
}

/// `PlayPauseIconFilled`: 48pt white circle with a dark 32pt glyph.
struct ParityPlayPauseButton: View {
    let isPlaying: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.black)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// An `IconButton(Icons.more_vert)` / generic 48pt tap target.
struct ParityIconButton: View {
    let systemName: String
    var rotation: Double = 0
    var size: CGFloat = 24
    var tooltip: String = ""
    var tint: Color = Color.white
    var frame: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .rotationEffect(.degrees(rotation))
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
    }
}

/// `Empty(text:)` (`lib/widgets/empty.dart`): centred text, w600, 16pt padding.
struct ParityEmptyText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// `ProgressSpinner`, centred, with Dart's 16pt vertical padding when used
/// as a pagination footer.
struct ParitySpinner: View {
    var fills = false
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(Color.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: fills ? 200 : nil)
    }
}
