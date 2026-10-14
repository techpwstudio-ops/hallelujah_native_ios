import SwiftUI

/// T54 contract — mirrors Dart's `showBookNotes` (`book_page_menu_sheet.dart`),
/// which lists notes purely from its local Realm cache rather than a live
/// fetch: `book.routes.js` has no bulk "list all my notes" endpoint (confirmed
/// by grep). `fetchLocalNotes()` here is the same shape, backed by this
/// platform's own on-device ledger (`CachedVerseNote`) instead of Realm.
@Observable
@MainActor
final class MyNotesViewModel {
    private(set) var notes: [BibleNoteEntry] = []
    private(set) var isLoading = true

    private let repository: any BibleRepository

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    func load() async {
        isLoading = true
        notes = await repository.fetchLocalNotes()
        isLoading = false
    }
}

/// `showBookNotes` (`lib/sheets/book/verse_show_notes_sheet.dart`) — every
/// note the reader has written, newest first, grouped by the chapter it
/// belongs to. Drag handle, a "Notes" caption (bodyLarge, white 70%), then a
/// "<Book> <chapter>" group header (bodySmall w700, white 70%) above each
/// run of note cards (8pt radius, 16pt padding, subtle border): "Verse N" and
/// the date (dd/MM/yyyy) on one row, a white "Notes" tag, then the note in
/// bodyLarge w300. Tapping a note jumps the reader to that verse.
///
/// Gap vs Flutter: `BibleNoteEntry` carries neither the verse text nor the
/// note's language, so the italic quoted verse and the "· Language" header
/// suffix cannot be drawn yet (domain change needed, outside this feature).
struct MyNotesView: View {
    let books: [BibleBook]
    let onSelect: (BibleNoteEntry) -> Void

    @State private var viewModel = MyNotesViewModel()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private enum Row: Identifiable {
        case header(id: String, title: String)
        case note(BibleNoteEntry)

        var id: String {
            switch self {
            case .header(let id, _): return "h-" + id
            case .note(let entry): return "n-" + entry.id
            }
        }
    }

    /// A header followed by that chapter's notes — chapters in the order they
    /// were last written in, notes inside a chapter in verse order.
    private var rows: [Row] {
        let usable = viewModel.notes
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
        var order: [String] = []
        var groups: [String: [BibleNoteEntry]] = [:]
        for note in usable {
            let key = "\(note.bookNumber)|\(note.chapterNumber)"
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(note)
        }
        var result: [Row] = []
        for key in order {
            guard let entries = groups[key], let first = entries.first else { continue }
            result.append(.header(id: key, title: "\(bookName(for: first)) \(first.chapterNumber)"))
            for entry in entries.sorted(by: { $0.verseNumber < $1.verseNumber }) {
                result.append(.note(entry))
            }
        }
        return result
    }

    private func bookName(for entry: BibleNoteEntry) -> String {
        books.first(where: { $0.bookNumber == entry.bookNumber })?.name ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadDragHandle()

            Text("Notes")
                .readText(Typography.bodyLarge, weight: .regular, color: ReadPalette.secondaryText)

            Spacer().frame(height: 12)

            content
        }
        .padding(.horizontal, 12)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        let currentRows = rows
        if viewModel.isLoading && viewModel.notes.isEmpty {
            ReadSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentRows.isEmpty {
            VStack(spacing: 0) {
                Image(systemName: "note.text")
                    .font(.system(size: 48))
                    .foregroundStyle(ReadPalette.secondaryText)
                Spacer().frame(height: 12)
                Text("No notes yet")
                    .readText(Typography.bodyLarge, weight: .medium, color: ReadPalette.secondaryText)
                Spacer().frame(height: 6)
                Text("Tap on a verse to add your first note")
                    .readText(Typography.bodySmall, color: ReadPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(currentRows) { row in
                        switch row {
                        case .header(_, let title):
                            Text(title)
                                .readText(Typography.bodySmall, weight: .bold, color: ReadPalette.secondaryText)
                                .padding(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 0))
                        case .note(let entry):
                            noteCard(entry)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func noteCard(_ entry: BibleNoteEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Verse \(entry.verseNumber)")
                        .readText(Typography.bodySmall, weight: .bold)
                    Spacer(minLength: 8)
                    Text(Self.dateFormatter.string(from: entry.updatedAt))
                        .readText(Typography.bodySmall, weight: .bold)
                }
                Spacer().frame(height: 8)
                Text("Notes")
                    .readText(Typography.bodySmall, weight: .bold, color: ReadPalette.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ReadPalette.white)
                    )
                Spacer().frame(height: 8)
                Text(entry.content)
                    .font(.custom(Typography.fontFamily, size: 16, relativeTo: .body).weight(.light))
                    .lineSpacing(16 * 0.5)
                    .foregroundStyle(ReadPalette.white)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ReadPalette.containerBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
