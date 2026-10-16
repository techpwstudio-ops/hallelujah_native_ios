import SwiftUI

/// The player's scrubber: `ProgressBar` from `audio_video_progress_bar` as
/// configured in `song_progress_bar.dart` — `thumbRadius: 6`, a round-capped
/// bar (`barHeight` 6 on the full player, 4 on the lyrics page), base track
/// `fillColor @ 0.8`, buffered track `fillColor`, white progress and thumb,
/// `bodySmall` time labels `timeLabelPadding: 8` below the bar. While
/// dragging, the thumb shows the package's soft glow (`thumbColor @ 0.2`).
/// Seeks on release, like the package's `onSeek`.
struct PlayerSeekBar: View {
    var position: TimeInterval
    var duration: TimeInterval
    var buffered: TimeInterval = 0
    var barHeight: CGFloat = PlayerStyle.seekBarHeight
    var isInteractive: Bool = true
    var onSeek: (TimeInterval) -> Void = { _ in }

    @State private var dragPosition: TimeInterval?

    private let thumbRadius = PlayerStyle.thumbRadius
    private let glowRadius: CGFloat = 30
    private let labelPadding: CGFloat = 8

    private var displayPosition: TimeInterval { dragPosition ?? position }

    private func fraction(_ value: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(value / duration, 0), 1))
    }

    var body: some View {
        VStack(spacing: labelPadding) {
            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width - thumbRadius * 2, 1)
                let progressX = trackWidth * fraction(displayPosition)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PlayerStyle.fill.opacity(0.8))
                        .frame(width: trackWidth, height: barHeight)
                        .offset(x: thumbRadius)
                    Capsule()
                        .fill(PlayerStyle.fill)
                        .frame(width: trackWidth * fraction(buffered), height: barHeight)
                        .offset(x: thumbRadius)
                    Capsule()
                        .fill(PlayerStyle.white)
                        .frame(width: progressX, height: barHeight)
                        .offset(x: thumbRadius)
                    if dragPosition != nil {
                        Circle()
                            .fill(PlayerStyle.whiteAlpha(0.2))
                            .frame(width: glowRadius * 2, height: glowRadius * 2)
                            .offset(x: progressX + thumbRadius - glowRadius)
                    }
                    Circle()
                        .fill(PlayerStyle.white)
                        .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                        .offset(x: progressX)
                }
                .frame(height: max(thumbRadius * 2, barHeight), alignment: .leading)
                .contentShape(Rectangle())
                .gesture(dragGesture(trackWidth: trackWidth))
                .allowsHitTesting(isInteractive)
            }
            .frame(height: max(thumbRadius * 2, barHeight))

            HStack {
                Text(Self.format(displayPosition))
                Spacer()
                Text(Self.format(duration))
            }
            .typography(PlayerStyle.timeLabel)
            .foregroundStyle(PlayerStyle.white)
        }
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragPosition = target(for: value.location.x, trackWidth: trackWidth)
            }
            .onEnded { value in
                let seekTarget = target(for: value.location.x, trackWidth: trackWidth)
                dragPosition = nil
                onSeek(seekTarget)
            }
    }

    private func target(for x: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        let clamped = min(max(x - thumbRadius, 0), trackWidth)
        return duration * Double(clamped / trackWidth)
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// The mini player's playback progress (`song_progress_bar.dart`'s
/// `preview: true` indicator), drawn along the pill's bottom border instead
/// of as a bar under it: the lower half of the outline of the same continuous
/// rounded rectangle the glass uses (from the middle of the left end, round
/// the bottom-left curve, along the flat, up the bottom-right curve to the
/// middle of the right end), filled left to right for `progress` of its
/// length. `progress == 1` is the whole bottom border, for the track behind.
///
/// Stroke this with `lineWidth == 2 * inset`: the path is inset by half the
/// stroke so the stroke's outer edge lands exactly on the glass edge.
struct PlayerProgressBottomBorder: Shape {
    var progress: Double
    /// The pill's corner radius (`Radius.full`), as given to the glass shape.
    var cornerRadius: CGFloat
    var inset: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return Path() }
        let outline = RoundedRectangle(cornerRadius: cornerRadius - inset, style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
        // `RoundedRectangle`'s path starts at 3 o'clock and runs clockwise
        // (and is symmetric), so its first half is exactly the bottom border,
        // traversed right to left and ending at 9 o'clock. Left-to-right
        // progress is therefore the stretch that ends there.
        let half = 0.5
        return outline.trimmedPath(from: half - half * fraction, to: half)
    }
}
