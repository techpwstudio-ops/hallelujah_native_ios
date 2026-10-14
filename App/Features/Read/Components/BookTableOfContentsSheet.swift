import SwiftUI

/// `BookTableOfContent` (`lib/sheets/book/table_of_content_sheet.dart`):
/// drag handle, a "Table of content" caption (bodyMedium, white 70%), then one
/// 56pt row per book — title titleMedium w700 (white when it is the book being
/// read, white 70% otherwise) with a 30pt white circle carrying the chapter
/// count. Tapping a row hands the book to `onSelect`; Flutter opens that
/// book's chapter grid (it does NOT switch the reader to the book yet). Like
/// Flutter, the list jumps to the current book when it is the 7th or later.
struct BookTableOfContentsSheet: View {
    let books: [BibleBook]
    let currentBookNumber: Int?
    let onSelect: (BibleBook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadDragHandle()

            Text("Table of content")
                .readText(Typography.bodyMedium, weight: .regular, color: ReadPalette.secondaryText)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(books) { book in
                            row(for: book)
                                .id(book.bookNumber)
                        }
                    }
                }
                .onAppear { scrollToCurrentBook(proxy) }
            }
        }
        .padding(.horizontal, Dimens.paddingMedium)
    }

    private func scrollToCurrentBook(_ proxy: ScrollViewProxy) {
        guard let currentBookNumber,
              let index = books.firstIndex(where: { $0.bookNumber == currentBookNumber }),
              index >= 6 else { return }
        proxy.scrollTo(currentBookNumber, anchor: .top)
    }

    private func row(for book: BibleBook) -> some View {
        let isCurrent = book.bookNumber == currentBookNumber
        return Button {
            onSelect(book)
        } label: {
            HStack(spacing: 0) {
                Text(book.name)
                    .readText(
                        Typography.titleMedium,
                        weight: .bold,
                        color: isCurrent ? ReadPalette.white : ReadPalette.secondaryText
                    )
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 16)
                Text("\(book.chapters)")
                    .readText(Typography.titleSmall, weight: .bold, color: ReadPalette.black)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(ReadPalette.white))
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
