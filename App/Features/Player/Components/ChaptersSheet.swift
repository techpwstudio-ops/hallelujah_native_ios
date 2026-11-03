import SwiftUI

/// The chapter list behind the player's Chapters button (Phase 1). One row per
/// chapter: artwork when the chapter has one, title, start time and length. The
/// current chapter is marked. Tapping a row seeks there and plays (the caller does both).
struct ChaptersSheet: View {
    let chapters: [EpisodeChapter]
    let position: TimeInterval
    let onSelect: (EpisodeChapter) -> Void

    private var currentChapterID: String? {
        chapters.last { Double($0.startMs) / 1000 <= position }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chapters")
                .typography(Typography.titleMedium)
                .foregroundStyle(PlayerStyle.white)
                .padding(.horizontal, PlayerStyle.pageSidePadding)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        chapterRow(chapter)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 8)
    }

    private func chapterRow(_ chapter: EpisodeChapter) -> some View {
        let isCurrent = chapter.id == currentChapterID
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(url: chapter.imageURL, width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(PlayerStyle.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(PlayerSeekBar.format(Double(chapter.startMs) / 1000))
                        Text(PlayerSeekBar.format(Double(chapter.endMs - chapter.startMs) / 1000))
                    }
                    .typography(PlayerStyle.timeLabel)
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ColorToken.brandPrimary.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PlayerStyle.pageSidePadding)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

#Preview("Chapters, dark") {
    ChaptersSheet(chapters: ChaptersSheet.previewChapters, position: 80) { _ in }
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}

#Preview("Chapters, light") {
    ChaptersSheet(chapters: ChaptersSheet.previewChapters, position: 80) { _ in }
        .background(PlayerStyle.black)
        .preferredColorScheme(.light)
}

extension ChaptersSheet {
    static let previewChapters: [EpisodeChapter] = [
        EpisodeChapter(id: "1", startMs: 0, endMs: 74_000, title: "Intro", imageURL: nil, linkURL: nil),
        EpisodeChapter(id: "2", startMs: 74_000, endMs: 1_500_000, title: "Reading: Mark 4:35-41",
                       imageURL: nil, linkURL: nil),
        EpisodeChapter(id: "3", startMs: 1_500_000, endMs: 3_600_000, title: "Sermon", imageURL: nil, linkURL: nil),
    ]
}
