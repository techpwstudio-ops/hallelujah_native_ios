import SwiftUI

/// T54 contract — presented as a `.sheet(item:)` from `ReaderView`/
/// `VerseRowView`'s "Note" context-menu action. Owns its own
/// `NavigationStack` for title + Cancel/Save chrome, the same shape
/// `AddSongsToPlaylistView` uses for any sheet that needs more than the
/// standard glass sheet container's drag handle (`AppSheetContainer` has no
/// toolbar slot).
struct VerseNoteEditorSheet: View {
    let verse: BibleVerse
    let existingNote: VerseNote?
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var text: String

    init(verse: BibleVerse, existingNote: VerseNote?, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.verse = verse
        self.existingNote = existingNote
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: existingNote?.content ?? "")
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Verse \(verse.verseNumber)")
                        .typography(Typography.labelLarge)
                        .foregroundStyle(theme.color(.textSecondary))
                    Text(verse.text)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textTertiary))
                        .lineLimit(3)
                }

                TextEditor(text: $text)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 160)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(theme.color(.surfaceInput))
                    }

                if existingNote != nil {
                    Button("Delete Note", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .background(theme.color(.backgroundPrimary))
            .navigationTitle(existingNote == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard !trimmedText.isEmpty else { return }
                        onSave(trimmedText)
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty)
                }
            }
        }
    }
}
