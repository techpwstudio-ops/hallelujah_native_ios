import SwiftUI

/// T57 — the Bible reader's "Listen" transport, shown as a slim inline bar
/// beneath the top bar while `ReadAloudController` has an active passage
/// (same placement convention as `ReaderView`'s own `boundaryBanner`, not a
/// sheet — there's no `.appSheet`/`.sheet` contract to follow here since
/// this isn't one of `ReaderView`'s doc-commented sheet components).
///
/// The progress track is a plain 0...1 fraction, not `SeekBar` (the Player
/// feature's own scrubber): `SeekBar` renders `mm:ss` position/duration
/// labels, which would show nonsensical clock time for a character-offset
/// count — this deliberately drops the time labels rather than mislabel
/// them, keeping the same Capsule-track/Circle-thumb/`DragGesture`
/// construction `SeekBar` already establishes for this codebase.
struct ListenControlBar: View {
    let status: ReadAloudController.Status
    let progress: Double
    let isRestarting: Bool
    let onTogglePlayPause: () -> Void
    let onSeek: (Double) -> Void
    let onStop: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var dragFraction: Double?

    private var displayedFraction: Double {
        dragFraction ?? progress
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onTogglePlayPause) {
                theme.icon(status == .playing ? .pause : .play)
                    .foregroundStyle(theme.color(.textOnBrand))
                    .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(isRestarting || status == .loading)

            track
                .frame(height: Self.thumbDiameter)
                .opacity(isRestarting ? 0.5 : 1)
                .allowsHitTesting(!isRestarting)

            Button(action: onStop) {
                theme.icon(.close)
                    .foregroundStyle(theme.color(.textOnBrand))
                    .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .glassCapsule(.tinted(.brandPrimary), interactive: true)
        .padding(.horizontal, Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private static let thumbDiameter: CGFloat = 12
    private static let barHeight: CGFloat = 4

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(min(max(displayedFraction, 0), 1))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.color(.textOnBrand).opacity(0.35))
                    .frame(height: Self.barHeight)
                Capsule(style: .continuous)
                    .fill(theme.color(.textOnBrand))
                    .frame(width: width * fraction, height: Self.barHeight)
                Circle()
                    .fill(theme.color(.textOnBrand))
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .offset(x: width * fraction - Self.thumbDiameter / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = min(max(value.location.x, 0), width)
                        dragFraction = width > 0 ? Double(clamped / width) : 0
                    }
                    .onEnded { value in
                        let clamped = min(max(value.location.x, 0), width)
                        let target = width > 0 ? Double(clamped / width) : 0
                        dragFraction = nil
                        onSeek(target)
                    }
            )
        }
    }
}
