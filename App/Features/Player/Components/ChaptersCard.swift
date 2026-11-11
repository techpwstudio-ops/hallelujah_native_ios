import SwiftUI

/// The chapter list of an episode, shown inline in the player's scrolling body
/// (it replaced the Chapters bottom sheet). It never covers the player: the
/// current chapter is always in view, so a listener sees where they are and
/// what comes next without opening anything.
///
/// Collapsed, it shows `collapsedRowCount` rows starting at the current chapter;
/// "Show all" opens the whole list in place. Each row has a number (a waveform
/// for the current chapter), the title ("Chapter N" when it has none), the start
/// time and the length. The current row also has a thin bar for the progress
/// inside that chapter. Tapping a row seeks there and plays (the caller does both).
/// `duration` closes the last chapter when the server sent no `endMs` for it.
///
/// The surface matches `ReadAlongCard`.
struct ChaptersCard: View {
    let chapters: [EpisodeChapter]
    let position: TimeInterval
    var duration: TimeInterval = 0
    var isPlaying: Bool = false
    let onSelect: (EpisodeChapter) -> Void

    @State private var isExpanded = false

    /// Rows shown while the card is collapsed.
    static let collapsedRowCount = 3

    private static let cardRadius: CGFloat = 20
    private static let headerToken = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1, tracking: 0.5)
    private static let buttonToken = TypographyToken(size: 12, weight: .semibold, lineHeightMultiple: 1, tracking: 0.3)
    private static let currentTitleToken = TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.5)
    private static let badgeWidth: CGFloat = 24

    private var durationMs: Int? { PlayerSeekBar.milliseconds(of: duration) }

    private var currentIndex: Int? {
        TimelineIndex(chapters: chapters).activeChapterIndex(positionMs: Int(position * 1000))
    }

    /// Whether the player shows this card for `chapters`. The mapper keeps no chapters for an
    /// episode with fewer than two, so an empty list is the only way to none.
    static func isShown(chapters: [EpisodeChapter]) -> Bool { !chapters.isEmpty }

    private var canExpand: Bool { chapters.count > Self.collapsedRowCount }

    private var visibleRows: Range<Int> {
        isExpanded
            ? chapters.indices
            : Self.collapsedRange(count: chapters.count, current: currentIndex)
    }

    /// The rows of the collapsed card: `visibleCount` rows beginning at the
    /// current chapter, pulled back near the end of the list so the card is
    /// never short. With no current chapter yet it starts at the first.
    static func collapsedRange(count: Int, current: Int?, visibleCount: Int = collapsedRowCount) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let shown = min(max(visibleCount, 1), count)
        let start = min(max(current ?? 0, 0), count - shown)
        return start..<(start + shown)
    }

    /// How far `positionMs` is through a chapter, from 0 to 1. `nil` while the
    /// chapter's end is unknown.
    static func progress(positionMs: Int, startMs: Int, endMs: Int?) -> Double? {
        guard let endMs, endMs > startMs else { return nil }
        return min(max(Double(positionMs - startMs) / Double(endMs - startMs), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            VStack(spacing: 0) {
                ForEach(Array(visibleRows), id: \.self) { index in
                    row(at: index)
                    if index != visibleRows.last {
                        Rectangle()
                            .fill(PlayerStyle.whiteAlpha(0.08))
                            .frame(height: 1)
                            .padding(.leading, Self.badgeWidth + 12)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [PlayerStyle.whiteAlpha(0.07), PlayerStyle.whiteAlpha(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .strokeBorder(PlayerStyle.whiteAlpha(0.12), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.25), value: visibleRows)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.number")
                .font(.system(size: 16))
                .accessibilityHidden(true)
            Text("Chapters")
            Text("\(chapters.count)")
                .foregroundStyle(PlayerStyle.whiteAlpha(0.4))
            Spacer(minLength: 8)
            if canExpand {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show less" : "Show all")
                        .typography(Self.buttonToken)
                        .foregroundStyle(PlayerStyle.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PlayerStyle.whiteAlpha(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .typography(Self.headerToken)
        .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
    }

    private func row(at index: Int) -> some View {
        let chapter = chapters[index]
        let isCurrent = index == currentIndex
        let endMs = chapter.effectiveEndMs(playerDurationMs: durationMs)
        let detail = detailText(startMs: chapter.startMs, endMs: endMs)
        return Button {
            onSelect(chapter)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                badge(index: index, isCurrent: isCurrent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.displayTitle(at: index))
                        .typography(isCurrent ? Self.currentTitleToken : Typography.bodyMedium)
                        .foregroundStyle(isCurrent ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .typography(PlayerStyle.timeLabel)
                        .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
                    if isCurrent, let fraction = Self.progress(
                        positionMs: Int(position * 1000),
                        startMs: chapter.startMs,
                        endMs: endMs
                    ) {
                        progressBar(fraction)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chapter.displayTitle(at: index))
        .accessibilityValue(detail)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The chapter's number, or a waveform (moving while playing) for the current one.
    @ViewBuilder
    private func badge(index: Int, isCurrent: Bool) -> some View {
        Group {
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColorToken.brandPrimary.color)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            } else {
                Text("\(index + 1)")
                    .typography(PlayerStyle.timeLabel)
                    .monospacedDigit()
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.5))
            }
        }
        .frame(width: Self.badgeWidth, height: 21)
        .accessibilityHidden(true)
    }

    private func progressBar(_ fraction: Double) -> some View {
        Capsule()
            .fill(PlayerStyle.whiteAlpha(0.12))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(ColorToken.brandPrimary.color)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .padding(.top, 3)
            .accessibilityHidden(true)
    }

    /// "02:15 · 12 min, 30 sec": the start time, then the length when the end is known.
    private func detailText(startMs: Int, endMs: Int?) -> String {
        let start = PlayerSeekBar.format(Double(startMs) / 1000)
        guard let endMs, endMs > startMs else { return start }
        let length = Duration.seconds((endMs - startMs) / 1000)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return "\(start) · \(length)"
    }
}

#Preview("Chapters card") {
    ScrollView {
        ChaptersCard(chapters: ChaptersCard.previewChapters, position: 80, duration: 3_600, isPlaying: true) { _ in }
            .padding(.horizontal, PlayerStyle.pageSidePadding)
    }
    .background(PlayerStyle.black)
    .preferredColorScheme(.dark)
}

extension ChaptersCard {
    static let previewChapters: [EpisodeChapter] = [
        EpisodeChapter(startMs: 0, endMs: 74_000, title: "Intro"),
        EpisodeChapter(startMs: 74_000, endMs: 1_500_000, title: "Reading: Mark 4:35-41"),
        EpisodeChapter(startMs: 1_500_000, endMs: 2_400_000, title: "Sermon: Peace in the storm"),
        EpisodeChapter(startMs: 2_400_000, endMs: 3_300_000, title: ""),
        EpisodeChapter(startMs: 3_300_000, endMs: nil, title: "Closing prayer"),
    ]
}
