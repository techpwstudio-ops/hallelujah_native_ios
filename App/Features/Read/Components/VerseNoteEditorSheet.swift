import SwiftUI

/// `showAddNotesSheet` (`lib/sheets/book/verse_add_notes_sheet.dart`): drag
/// handle, the verse quoted between bold-italic quotation marks, a
/// "<Book> . <chapter> . <verse>" line, "Enter Notes", a 6–8 line field
/// (black fill, 8pt radius, hint "Enter"), a white "Save" button (empty note:
/// toast "Please enter note") and an outlined "Remove" (existing note) /
/// "Cancel" button.
struct VerseNoteEditorSheet: View {
    let verse: BibleVerse
    let bookName: String
    let existingNote: VerseNote?
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastCenter) private var toastCenter
    @State private var text: String

    init(
        verse: BibleVerse,
        bookName: String,
        existingNote: VerseNote?,
        onSave: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.verse = verse
        self.bookName = bookName
        self.existingNote = existingNote
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: existingNote?.content ?? "")
    }

    private var quoteGlyph: Text {
        Text("\"")
            .font(.custom(Typography.fontFamily, size: 20, relativeTo: .body).weight(.bold).italic())
    }

    private var quote: Text {
        quoteGlyph
            + Text(" \(verse.verseNumber). \(verse.text) ")
                .font(.custom(Typography.fontFamily, size: 16, relativeTo: .body).weight(.light))
            + quoteGlyph
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReadDragHandle()

                quote
                    .foregroundStyle(ReadPalette.white)
                    .lineSpacing(16 * 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(height: 4)

                Text("\(bookName) . \(verse.chapterNumber) . \(verse.verseNumber)")
                    .readText(Typography.titleSmall, weight: .bold)

                Spacer().frame(height: 24)

                Text("Enter Notes")
                    .readText(Typography.titleMedium, weight: .medium)

                Spacer().frame(height: 8)

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Enter").foregroundColor(ReadPalette.hint),
                    axis: .vertical
                )
                .typography(Typography.bodyLarge)
                .foregroundStyle(ReadPalette.white)
                .lineLimit(6...8)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(ReadPalette.black)
                )

                Spacer().frame(height: 24)

                Button(action: save) {
                    Text("Save")
                        .readText(Typography.titleMedium, color: ReadPalette.background)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                                .fill(ReadPalette.white)
                        )
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 16)

                Button(action: removeOrCancel) {
                    Text(existingNote != nil ? "Remove" : "Cancel")
                        .readText(Typography.titleMedium)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                                .strokeBorder(ReadPalette.white, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        if text.isEmpty {
            toastCenter.show("Please enter note")
            return
        }
        dismiss()
        onSave(text)
    }

    private func removeOrCancel() {
        dismiss()
        if existingNote != nil {
            onDelete()
        }
    }
}
