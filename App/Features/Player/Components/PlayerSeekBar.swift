import SwiftUI

/// The player's scrubber: `ProgressBar` from `audio_video_progress_bar` as
/// configured in `song_progress_bar.dart` — `thumbRadius: 6`, a round-capped
/// bar (`barHeight` 6 on the full player, 4 on the lyrics page), base track
/// `fillColor @ 0.8`, buffered track `fillColor`, white progress and thumb,
/// `bodySmall` time labels `timeLabelPadding: 8` below the bar. While
/// dragging, the thumb shows the package's soft glow (`thumbColor @ 0.2`).
/// Seeks on release, like the package's `onSeek`.
///
/// With `chapters` (two or more, Phase 1) the track is drawn as one segment per
/// chapter, and the current chapter's title sits between the time labels. With
/// the default empty `chapters` every caller renders exactly as before.
/// A chapter's end is its `endMs`, else this bar's `duration` (the last chapter
/// can have no `endMs`), and its title is "Chapter N" when the server sent none.
struct PlayerSeekBar: View {
    var position: TimeInterval
    var duration: TimeInterval
    var buffered: TimeInterval = 0
    var barHeight: CGFloat = PlayerStyle.seekBarHeight
    var isInteractive: Bool = true
    var chapters: [EpisodeChapter] = []
    var onSeek: (TimeInterval) -> Void = { _ in }

    @State private var dragPosition: TimeInterval?
    @State private var dragChapterIndex: Int?

    private let thumbRadius = PlayerStyle.thumbRadius
    private let glowRadius: CGFloat = 30
    private let labelPadding: CGFloat = 8
    /// Chapter track heights while scrubbing: 4 pt at rest, 8 pt while dragging.
    private static let chapterRestingHeight: CGFloat = 4
    private static let chapterDraggingHeight: CGFloat = 8
    private static let dragLabelWidth: CGFloat = 180

    private var displayPosition: TimeInterval { dragPosition ?? position }

    private var hasChapters: Bool { !chapters.isEmpty }

    /// The bar's duration in whole milliseconds, or `nil` while it is unknown.
    private var durationMs: Int? {
        PlayerSeekBar.milliseconds(of: duration)
    }

    /// Each chapter's span in seconds. A last chapter with no end and no known
    /// duration stays open-ended (`end` is `nil`), and the layout sizes it.
    private var chapterSpans: [(start: Double, end: Double?)] {
        chapters.map { chapter in
            (
                start: Double(chapter.startMs) / 1000,
                end: chapter.effectiveEndMs(playerDurationMs: durationMs).map { Double($0) / 1000 }
            )
        }
    }

    private var trackHeight: CGFloat {
        guard hasChapters else { return barHeight }
        return dragPosition == nil ? Self.chapterRestingHeight : Self.chapterDraggingHeight
    }

    /// The chapter playing at `seconds`: the last one that has started.
    private func chapterIndex(at seconds: TimeInterval) -> Int? {
        chapters.lastIndex { Double($0.startMs) / 1000 <= seconds }
    }

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
                    if hasChapters {
                        chapterSegments(trackWidth: trackWidth)
                    } else {
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
                    }
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
                .frame(height: max(thumbRadius * 2, trackHeight), alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: trackHeight)
                .overlay(alignment: .topLeading) {
                    if let index = dragChapterIndex, chapters.indices.contains(index) {
                        dragLabel(for: chapters[index], at: index, thumbX: progressX, trackWidth: trackWidth)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(trackWidth: trackWidth))
                .allowsHitTesting(isInteractive)
            }
            .frame(height: max(thumbRadius * 2, trackHeight))

            timeLabels
        }
        .modifier(ChapterSeekAccessibility(
            chapters: chapters,
            position: displayPosition,
            onSeek: onSeek
        ))
    }

    /// The original labels, unchanged, when there are no chapters.
    @ViewBuilder
    private var timeLabels: some View {
        if hasChapters {
            HStack(spacing: labelPadding) {
                Text(Self.format(displayPosition))
                    .fixedSize()
                if let index = chapterIndex(at: displayPosition) {
                    Text(chapters[index].displayTitle(at: index))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer()
                }
                Text(Self.format(duration))
                    .fixedSize()
            }
            .typography(PlayerStyle.timeLabel)
            .foregroundStyle(PlayerStyle.white)
        } else {
            HStack {
                Text(Self.format(displayPosition))
                Spacer()
                Text(Self.format(duration))
            }
            .typography(PlayerStyle.timeLabel)
            .foregroundStyle(PlayerStyle.white)
        }
    }

    /// One segment per drawn chapter group. Each fills with its own played
    /// fraction, over its own buffered fraction (the lighter shade), over the base.
    private func chapterSegments(trackWidth: CGFloat) -> some View {
        ForEach(ChapterSegmentLayout.segments(spans: chapterSpans, trackWidth: trackWidth)) { segment in
            Capsule()
                .fill(PlayerStyle.fill.opacity(0.8))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(PlayerStyle.fill)
                        .frame(width: segment.width * CGFloat(segment.playedFraction(at: buffered)))
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(PlayerStyle.white)
                        .frame(width: segment.width * CGFloat(segment.playedFraction(at: displayPosition)))
                }
                .frame(width: segment.width, height: trackHeight)
                .offset(x: thumbRadius + segment.startX)
        }
    }

    /// The chapter title and time above the thumb while scrubbing.
    private func dragLabel(
        for chapter: EpisodeChapter,
        at index: Int,
        thumbX: CGFloat,
        trackWidth: CGFloat
    ) -> some View {
        let widest = trackWidth + thumbRadius * 2 - Self.dragLabelWidth
        let left = min(max(thumbX + thumbRadius - Self.dragLabelWidth / 2, 0), max(widest, 0))
        return VStack(spacing: 2) {
            Text(chapter.displayTitle(at: index))
                .lineLimit(1)
            Text(Self.format(displayPosition))
        }
        .typography(PlayerStyle.timeLabel)
        .foregroundStyle(PlayerStyle.white)
        .frame(width: Self.dragLabelWidth)
        .offset(x: left, y: -36)
        .allowsHitTesting(false)
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let newTarget = target(for: value.location.x, trackWidth: trackWidth)
                dragPosition = newTarget
                if hasChapters {
                    let newIndex = chapterIndex(at: newTarget)
                    if newIndex != dragChapterIndex {
                        dragChapterIndex = newIndex
                        HapticFeedback.impact(.light).trigger()
                    }
                }
            }
            .onEnded { value in
                let seekTarget = target(for: value.location.x, trackWidth: trackWidth)
                dragPosition = nil
                dragChapterIndex = nil
                onSeek(seekTarget)
            }
    }

    private func target(for x: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        let clamped = min(max(x - thumbRadius, 0), trackWidth)
        return duration * Double(clamped / trackWidth)
    }

    /// Whole milliseconds of `seconds`, or `nil` for a duration that is not known yet
    /// (zero, negative, or not a finite number).
    static func milliseconds(of seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Int((seconds * 1000).rounded())
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// VoiceOver for the chapter track: the value names the chapter, and swiping
/// up or down moves to the next or previous chapter. Applied only with chapters,
/// so the plain bar keeps its current accessibility.
private struct ChapterSeekAccessibility: ViewModifier {
    let chapters: [EpisodeChapter]
    let position: TimeInterval
    let onSeek: (TimeInterval) -> Void

    func body(content: Content) -> some View {
        if chapters.isEmpty {
            content
        } else {
            content
                .accessibilityValue(valueText)
                .accessibilityAdjustableAction { direction in
                    adjust(direction)
                }
        }
    }

    private var currentIndex: Int {
        chapters.lastIndex { Double($0.startMs) / 1000 <= position } ?? 0
    }

    /// "Chapter 3 of 12, <title>". With no title the title would only repeat the
    /// number, so the announcement stops at "Chapter 3 of 12".
    private var valueText: String {
        let current = currentIndex
        let chapter = chapters[current]
        guard chapter.hasTitle else {
            return String(localized: "Chapter \(current + 1) of \(chapters.count)")
        }
        return String(localized: "Chapter \(current + 1) of \(chapters.count), \(chapter.title)")
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let current = currentIndex
        switch direction {
        case .increment:
            guard current + 1 < chapters.count else { return }
            onSeek(Double(chapters[current + 1].startMs) / 1000)
        case .decrement:
            // Within a few seconds of a chapter's start, "back" goes to the previous chapter.
            let start = Double(chapters[current].startMs) / 1000
            if position > start + 3 {
                onSeek(start)
            } else {
                onSeek(Double(chapters[max(current - 1, 0)].startMs) / 1000)
            }
        default:
            break
        }
    }
}

/// The mini player's playback progress (`song_progress_bar.dart`'s
/// `preview: true` indicator), drawn along the pill's bottom border instead
/// of as a bar under it: a straight line on the bottom edge of the same
/// continuous rounded rectangle the glass uses, filled left to right for
/// `progress` of its length. It starts where the left end curve has come down
/// to within `2 * inset` of the bottom (the stroke's own thickness) and stops
/// at the mirror point on the right, so it never bends up the ends — and its
/// first sliver sits on the baseline, not halfway up the pill's side.
/// `progress == 1` is the whole line, for the track behind.
///
/// Stroke this with `lineWidth == 2 * inset`: the line is inset by half the
/// stroke so the stroke's outer edge lands exactly on the glass edge.
struct PlayerProgressBottomBorder: Shape {
    var progress: Double
    /// The pill's corner radius (`Radius.full`), as given to the glass shape.
    var cornerRadius: CGFloat
    var inset: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let fraction = min(max(progress, 0), 1)
        guard fraction > 0 else { return Path() }
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let outline = RoundedRectangle(cornerRadius: cornerRadius - inset, style: .continuous)
            .path(in: insetRect)
        let rightEnd = Self.baselineRightEnd(of: outline, bottom: insetRect.maxY, rise: 2 * inset)
        let leftEnd = insetRect.minX + insetRect.maxX - rightEnd // mirror image about the centre
        var path = Path()
        path.move(to: CGPoint(x: leftEnd, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: leftEnd + (rightEnd - leftEnd) * fraction, y: insetRect.maxY))
        return path
    }

    /// The x at which the outline's bottom-right curve first comes within
    /// `rise` of `bottom`. `RoundedRectangle`'s path starts at 3 o'clock and
    /// runs clockwise, so the first quarter of it reaches 6 o'clock; bisecting
    /// that quarter on the outline itself (rather than assuming a circular
    /// arc) keeps this right for the continuous (squircle) corner.
    private static func baselineRightEnd(of outline: Path, bottom: CGFloat, rise: CGFloat) -> CGFloat {
        var low = 0.0
        var high = 0.25 // 6 o'clock: always at the bottom
        var x = outline.boundingRect.midX
        for _ in 0..<24 {
            let middle = (low + high) / 2
            guard let point = outline.trimmedPath(from: 0, to: middle).currentPoint else {
                low = middle
                continue
            }
            if bottom - point.y <= rise {
                high = middle
                x = point.x
            } else {
                low = middle
            }
        }
        return x
    }
}
