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

/// Presented as a plain `.sheet(isPresented:)` from `ReaderView`'s "My
/// Notes" toolbar action (T54 contract) — not `coordinator.push(...)`, since
/// no `AppRoute` case exists for "open my notes" and this feature is
/// forbidden from adding one to `AppRoute.swift`. Read-only in v1: tapping a
/// row does not navigate back into the reader at that position either, for
/// the same reason (no "open reader at position" `AppRoute` case, and adding
/// one is out of scope here) — a documented scope cut, not an oversight.
struct MyNotesView: View {
    let books: [BibleBook]

    @State private var viewModel = MyNotesViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            content
                .background(theme.color(.backgroundPrimary))
                .navigationTitle("My Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            LoadingStateView()
                .frame(maxHeight: .infinity)
        } else if viewModel.notes.isEmpty {
            EmptyStateView(
                title: "No Notes Yet",
                message: "Notes you add while reading will show up here."
            )
            .frame(maxHeight: .infinity)
        } else {
            List(viewModel.notes) { entry in
                row(for: entry)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func displayName(for entry: BibleNoteEntry) -> String {
        books.first(where: { $0.bookNumber == entry.bookNumber })?.name ?? "Book \(entry.bookNumber)"
    }

    private func row(for entry: BibleNoteEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(displayName(for: entry)) \(entry.chapterNumber):\(entry.verseNumber)")
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
            Text(entry.content)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
                .lineLimit(3)
        }
        .padding(.vertical, Spacing.xs)
        .listRowBackground(Color.clear)
    }
}
