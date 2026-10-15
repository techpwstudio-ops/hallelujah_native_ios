import SwiftUI

/// Ports `SongLyricsDetails` + `LyricsPreview` (`lib/widgets/player/
/// lyrics_ui.dart`, `lyrics_preview.dart`): a 20pt-radius card (top-left to
/// bottom-right gradient white 7% -> 3%, 1pt white 12% border) holding a
/// "Lyrics" header, a 220pt non-interactive, position-synced preview with
/// faded edges, and a "View Full Lyrics" pill. Shown only when the song has
/// transcripts. The active line is `lastIndexWhere(start <= position)`; the
/// preview scrolls it to 40% of the viewport over 350 ms easeOutCubic.
struct PlayerLyricsPreviewCard: View {
    let song: Song
    let currentPosition: TimeInterval
    let onViewFull: () -> Void

    private static let previewHeight: CGFloat = 220
    private static let cardRadius: CGFloat = 20
    private static let scrollAnimation = Animation.timingCurve(0.215, 0.61, 0.355, 1.0, duration: 0.35)
    /// `labelLarge` with w500 / 0.5 tracking, `labelMedium` with w600 / 0.3.
    private static let headerToken = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1, tracking: 0.5)
    private static let buttonToken = TypographyToken(size: 12, weight: .semibold, lineHeightMultiple: 1, tracking: 0.3)
    private static let topAnchorID = "lyrics-preview-top"

    private var transcripts: [LyricsTranscript] { song.transcripts ?? [] }

    private var activeIndex: Int? {
        var result: Int?
        for (index, line) in transcripts.enumerated() where currentPosition >= line.startTime {
            result = index
        }
        return result
    }

    var body: some View {
        if !transcripts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                preview
                    .frame(height: Self.previewHeight)
                    .padding(.top, 10)
                viewFullButton
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
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
            .padding(.vertical, 12)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 16))
                .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
            Text("Lyrics")
                .typography(Self.headerToken)
                .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
        }
    }

    private var preview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, line in
                        LyricsLineItem(
                            text: line.text ?? "",
                            isActive: index == activeIndex,
                            isPast: activeIndex.map { index < $0 } ?? false
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDisabled(true)
            .allowsHitTesting(false)
            .mask(LyricsEdgeFadeMask())
            .onAppear {
                // First-frame sync (`_updateForSeconds` in `initState`).
                if let index = activeIndex, transcripts.indices.contains(index) {
                    proxy.scrollTo(transcripts[index].id, anchor: UnitPoint(x: 0.5, y: 0.4))
                }
            }
            .onChange(of: activeIndex) { _, newValue in
                withAnimation(Self.scrollAnimation) {
                    if let newValue, transcripts.indices.contains(newValue) {
                        proxy.scrollTo(transcripts[newValue].id, anchor: UnitPoint(x: 0.5, y: 0.4))
                    } else {
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                }
            }
        }
    }

    private var viewFullButton: some View {
        Button(action: onViewFull) {
            Text("View Full Lyrics")
                .typography(Self.buttonToken)
                .foregroundStyle(PlayerStyle.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(PlayerStyle.whiteAlpha(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(PlayerStyle.whiteAlpha(0.2), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}
