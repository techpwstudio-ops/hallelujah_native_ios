import SwiftUI

/// Interactive, draggable playback scrubber — native port of `ProgressBar`
/// as configured by `song_progress_bar.dart`'s non-preview branch:
/// `thumbRadius: 6`, `barHeight: 4.0` (default), a buffered track, and
/// position/duration time labels either side.
///
/// Colors are Dart's own literal white-on-dark player palette
/// (`progressBarColor: Colors.white`, `thumbColor: whiteColor`,
/// `baseBarColor`/`bufferedBarColor` off `ColorTheme.fillColor`) — the
/// player chrome there is always dark regardless of the app theme, so this
/// maps that fixed intent onto `textInverse` (which adapts with light/dark
/// automatically) rather than a literal `Color.white`, the same substitution
/// `ShimmerModifier` already established for this app's other Dart-hardcoded
/// player-adjacent color.
struct SeekBar: View {
    var position: TimeInterval
    var duration: TimeInterval
    var buffered: TimeInterval = 0
    var barHeight: CGFloat = 4
    var onSeek: (TimeInterval) -> Void

    @Environment(\.appTheme) private var theme
    @State private var dragPosition: TimeInterval?

    private static let thumbDiameter: CGFloat = 12 // thumbRadius: 6

    private var displayPosition: TimeInterval { dragPosition ?? position }

    private func fraction(_ value: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(value / duration, 0), 1))
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let progressFraction = fraction(displayPosition)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(theme.color(.textInverse).opacity(0.24))
                        .frame(height: barHeight)
                    Capsule(style: .continuous)
                        .fill(theme.color(.textInverse).opacity(0.5))
                        .frame(width: width * fraction(buffered), height: barHeight)
                    Capsule(style: .continuous)
                        .fill(theme.color(.textInverse))
                        .frame(width: width * progressFraction, height: barHeight)
                    Circle()
                        .fill(theme.color(.textInverse))
                        .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                        .offset(x: width * progressFraction - Self.thumbDiameter / 2)
                }
                .frame(height: Self.thumbDiameter)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = min(max(value.location.x, 0), width)
                            dragPosition = duration * Double(clamped / width)
                        }
                        .onEnded { value in
                            let clamped = min(max(value.location.x, 0), width)
                            let seekTarget = duration * Double(clamped / width)
                            dragPosition = nil
                            onSeek(seekTarget)
                        }
                )
            }
            .frame(height: Self.thumbDiameter)

            HStack {
                Text(Self.format(displayPosition))
                Spacer()
                Text(Self.format(duration))
            }
            .typography(Typography.bodySmall)
            .foregroundStyle(theme.color(.textSecondary))
            .padding(.horizontal, Spacing.sm) // matches timeLabelPadding: 8
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
