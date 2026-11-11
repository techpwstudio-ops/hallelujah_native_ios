import SwiftUI
import Testing
@testable import Hallelujah

@MainActor
struct PlayerChipRowTests {
    @Test func theRowIsEmptyWithNoVideoAndNoChapters() {
        #expect(PlayerChipRow.isEmpty(hasVideo: false, hasChapters: false))
    }

    @Test func aVideoAloneFillsTheRow() {
        #expect(!PlayerChipRow.isEmpty(hasVideo: true, hasChapters: false))
    }

    @Test func chaptersAloneFillTheRow() {
        #expect(!PlayerChipRow.isEmpty(hasVideo: false, hasChapters: true))
    }

    @Test func bothFillTheRow() {
        #expect(!PlayerChipRow.isEmpty(hasVideo: true, hasChapters: true))
    }

    @Test func anEmptyRowTakesNoSpaceAtAll() {
        let row = PlayerChipRow(
            hasVideo: false,
            isShowingVideo: false,
            hasChapters: false,
            onToggleMedia: {},
            onShowChapters: {}
        )
        let size = UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: 335, height: 1_000))
        #expect(size == .zero)
    }

    @Test func theChaptersChipFollowsTheCardsOwnRule() {
        #expect(!ChaptersCard.isShown(chapters: []))
        #expect(ChaptersCard.isShown(chapters: ChaptersCard.previewChapters))
    }

    @Test func theChaptersChipUsesTheCardHeadersLabelAndAListGlyph() {
        #expect(PlayerChipRow.chaptersTitle == "Chapters")
        #expect(PlayerChipRow.chaptersSystemName == "list.bullet")
    }
}

struct PlayerChipFlowLayoutTests {
    private func lines(_ widths: [CGFloat], in available: CGFloat) -> [[Int]] {
        PlayerChipFlowLayout.lines(widths: widths, available: available, spacing: 8)
    }

    @Test func twoChipsShareALineWhenTheyFit() {
        // 150 + 8 + 150 = 308
        #expect(lines([150, 150], in: 335) == [[0, 1]])
    }

    @Test func theSecondChipWrapsWhenTheyDoNotFit() {
        // 170 + 8 + 170 = 348 > 335
        #expect(lines([170, 170], in: 335) == [[0], [1]])
    }

    @Test func theGapCountsTowardsFitting() {
        #expect(lines([100, 100], in: 208) == [[0, 1]])
        #expect(lines([100, 100], in: 207) == [[0], [1]])
    }

    @Test func aChipWiderThanTheLineStillGetsALineOfItsOwn() {
        #expect(lines([400, 100], in: 335) == [[0], [1]])
    }

    @Test func noChipsMakeNoLines() {
        #expect(lines([], in: 335).isEmpty)
    }
}
