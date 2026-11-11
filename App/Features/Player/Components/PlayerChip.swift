import SwiftUI

/// The pill under the artwork that does one thing: a glyph and a short label in a white-on-dark
/// capsule. "Switch to video / audio" and "Chapters" are both this view, so they are the same size
/// and style. The capsule is 34 pt tall; the button around it is 44 pt, so it is easy to hit.
///
/// A label too long for the line wraps onto a second line rather than being cut off.
struct PlayerChip: View {
    let systemName: String
    let title: String
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button {
            HapticFeedback.selection.trigger()
            action()
        } label: {
            HStack(spacing: Dimens.spacing6) {
                Image(systemName: systemName)
                    .font(.system(size: PlayerStyle.chipGlyphSize, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .typography(PlayerStyle.chipLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // One line at its natural width; wraps, never truncates, when the line is short.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PlayerStyle.white)
            .padding(.horizontal, Dimens.spacing12)
            .frame(minHeight: PlayerStyle.chipHeight)
            .background(PlayerStyle.chipFill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(PlayerStyle.chipBorder, lineWidth: 1 / displayScale)
            }
            // The capsule is smaller than a finger; the button around it is not.
            .frame(minHeight: PlayerStyle.chipHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlayerChipButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// A chip dims to 60 percent while a finger is on it.
struct PlayerChipButtonStyle: ButtonStyle {
    static let pressedOpacity: Double = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(.easeOut(duration: MotionDuration.fast), value: configuration.isPressed)
    }
}

/// The row of chips between the artwork and the song's title, on the player's 20 pt gutter (the
/// caller's padding). It holds "Switch to video / audio" while the episode has a video and
/// "Chapters" while it has the chapters card. With neither it draws nothing and takes no space.
struct PlayerChipRow: View {
    let hasVideo: Bool
    let isShowingVideo: Bool
    let hasChapters: Bool
    let onToggleMedia: () -> Void
    let onShowChapters: () -> Void

    /// No video to switch to and no chapters to jump to: nothing to draw, so the screen is as it
    /// was before the row existed.
    static func isEmpty(hasVideo: Bool, hasChapters: Bool) -> Bool {
        !hasVideo && !hasChapters
    }

    /// The Chapters chip's glyph and label (the label is the card header's own string).
    static let chaptersSystemName = "list.bullet"

    static var chaptersTitle: String { String(localized: "Chapters") }

    var body: some View {
        if !Self.isEmpty(hasVideo: hasVideo, hasChapters: hasChapters) {
            PlayerChipFlowLayout(spacing: Dimens.spacing8) {
                if hasVideo {
                    MediaModeToggle(isShowingVideo: isShowingVideo, action: onToggleMedia)
                }
                if hasChapters {
                    PlayerChip(
                        systemName: Self.chaptersSystemName,
                        title: Self.chaptersTitle,
                        action: onShowChapters
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PlayerStyle.chipRowTopInset)
            .padding(.bottom, PlayerStyle.chipRowBottomInset)
        }
    }
}

/// Lays chips out left to right with `spacing` between them. A chip that does not fit on the line
/// goes to a line of its own, and a chip wider than the whole line is given the line's width, so
/// its label wraps instead of running off the screen. The chips are 44 pt boxes already, so lines
/// stack with no space between them.
struct PlayerChipFlowLayout: Layout {
    var spacing: CGFloat

    /// Which chips share a line, in order. A chip goes on the current line while it fits within
    /// `available`; the first chip of a line always stays, however wide.
    static func lines(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if lines.isEmpty || used + spacing + width > available {
                lines.append([index])
                used = width
            } else {
                lines[lines.count - 1].append(index)
                used += spacing + width
            }
        }
        return lines
    }

    private struct Arrangement {
        var frames: [CGRect]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(available: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(available: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = arrangement.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(available: CGFloat, subviews: Subviews) -> Arrangement {
        let sizes = subviews.map { subview -> CGSize in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > available else { return ideal }
            return subview.sizeThatFits(ProposedViewSize(width: available, height: nil))
        }
        let lines = Self.lines(widths: sizes.map(\.width), available: available, spacing: spacing)
        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        var y: CGFloat = 0
        var widest: CGFloat = 0
        for line in lines {
            var x: CGFloat = 0
            for index in line {
                frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: sizes[index])
                x += sizes[index].width + spacing
            }
            widest = max(widest, x - spacing)
            y += line.map { sizes[$0].height }.max() ?? 0
        }
        return Arrangement(frames: frames, size: CGSize(width: widest, height: y))
    }
}

#Preview("Chip row: video and chapters") {
    VStack(alignment: .leading, spacing: 0) {
        PlayerChipRow(
            hasVideo: true,
            isShowingVideo: false,
            hasChapters: true,
            onToggleMedia: {},
            onShowChapters: {}
        )
        PlayerChipRow(
            hasVideo: true,
            isShowingVideo: true,
            hasChapters: true,
            onToggleMedia: {},
            onShowChapters: {}
        )
        .environment(\.dynamicTypeSize, .accessibility2)
    }
    .padding(.horizontal, PlayerStyle.pageSidePadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(PlayerStyle.black)
    .preferredColorScheme(.dark)
}
