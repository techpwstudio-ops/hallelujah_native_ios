import SwiftUI

/// `TotalChaptersSheet` (`lib/sheets/book/table_chapter_sheet.dart`): drag
/// handle, a back row ("‹" + the book name, bodyLarge white 70%) that returns
/// to the table of contents, an 8pt gap, then a 6-column grid (8pt gaps,
/// square cells, 8pt radius) of chapter numbers — #212121 tiles with white
/// titleMedium w700 numbers, the chapter being read shown as a white tile with
/// black text. Padded 8 all round. Like Flutter, the grid scrolls the current
/// chapter into view when its row is the 7th or later.
struct ChapterGridSheet: View {
    let book: BibleBook
    /// The reader's Bible language — the back row shows the translated name.
    var language: String? = nil
    /// Chapter currently open in the reader, only meaningful when
    /// `currentBookNumber == book.bookNumber`.
    let currentChapter: Int
    let currentBookNumber: Int?
    let onBack: () -> Void
    let onSelect: (Int) -> Void

    @Environment(\.layoutWidth) private var layoutWidth

    private static let columnCount = 6

    /// Flutter's six columns; a wider sheet gets more (native-only tablet/Mac
    /// adaptation) so the 48pt tiles keep roughly their phone spacing.
    private static func gridColumnCount(in width: CGFloat) -> Int {
        AdaptiveLayout.columns(phone: columnCount, minItemWidth: 64, in: width)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.gridColumnCount(in: layoutWidth))
    }

    private var chapterRange: [Int] {
        book.chapters > 0 ? Array(1...book.chapters) : []
    }

    private var isCurrentBook: Bool { currentBookNumber == book.bookNumber }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadDragHandle()

            Button(action: onBack) {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(ReadPalette.white)
                        .frame(width: 24, height: 24)
                    Text(book.translate(language))
                        .readText(Typography.bodyLarge, weight: .regular, color: ReadPalette.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: Dimens.bottomPadding)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(chapterRange, id: \.self) { chapter in
                            cell(for: chapter)
                                .id(chapter)
                        }
                    }
                }
                .onAppear {
                    guard isCurrentBook, currentChapter > 0 else { return }
                    let row = (currentChapter - 1) / Self.gridColumnCount(in: layoutWidth)
                    if row >= 6 {
                        proxy.scrollTo(currentChapter, anchor: .top)
                    }
                }
            }
        }
        .padding(8)
    }

    /// Flutter's grid cell is `(width - 16 - 40) / 6` square and the tile in it
    /// is a fixed 48x48 `MyContainer`, centred — so the tile never hugs its
    /// number.
    private func cell(for chapter: Int) -> some View {
        let isCurrent = isCurrentBook && chapter == currentChapter
        return Button {
            onSelect(chapter)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: Dimens.chapterNumberBoxRadius, style: .continuous)
                        .fill(isCurrent ? ReadPalette.white : ReadPalette.chapterBox)
                        .frame(width: Self.tileSize, height: Self.tileSize)
                        .overlay {
                            Text("\(chapter)")
                                .readText(
                                    Typography.titleMedium,
                                    weight: .bold,
                                    color: isCurrent ? ReadPalette.black : ReadPalette.white
                                )
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let tileSize: CGFloat = 48

    /// Flutter caps the sheet at 70% of the screen but lets it shrink to its
    /// content: drag handle + back row + gap + grid rows. Mirrors that so a
    /// 21-chapter book doesn't open as a mostly empty 70% panel.
    ///
    /// `width` and `screenHeight` are the window's — the screen on a phone —
    /// rather than `UIScreen`'s, which is the whole display in Split View and
    /// on a Mac (native-only tablet/Mac adaptation).
    static func sheetHeight(chapterCount: Int, width: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let count = gridColumnCount(in: width)
        let rows = CGFloat((max(chapterCount, 1) + count - 1) / count)
        // 8pt sheet padding each side, 8pt between columns.
        let cell = max((width - 16 - 8 * CGFloat(count - 1)) / CGFloat(count), 0)
        let grid = rows * cell + (rows - 1) * 8
        let chrome: CGFloat = 8 + 28 + 24 + Dimens.bottomPadding + 8 + 34
        // Unmeasured window (before the reader's first layout): uncapped, never a zero detent.
        return screenHeight > 0 ? min(chrome + grid, screenHeight * 0.7) : chrome + grid
    }
}
