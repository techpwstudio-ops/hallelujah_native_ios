import SwiftUI

/// Save / unsave toggle for an album, season or company playlist
/// (`AddToLibraryButton`, `lib/widgets/playlists/add_to_library_button.dart`).
/// Reads the shared `LibrarySavedStore`, so every instance flips together.
///
/// Removing asks for confirmation; saving doesn't (saving is trivially
/// undoable, an unsave has no undo) — the same one-sided gate Dart uses, and
/// the same one the container menu goes through.
struct AddToLibraryButton: View {
    let type: LibraryItemType
    let itemID: String
    /// Named in the removal confirmation.
    var title: String?

    @State private var store: LibrarySavedStore = DependencyContainer.current.resolve()
    @State private var isConfirmingRemoval = false
    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    private var isSaved: Bool { store.isSaved(type, id: itemID) }

    var body: some View {
        Button {
            if isSaved { isConfirmingRemoval = true } else { toggle() }
        } label: {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 26))
                .foregroundStyle(isSaved ? theme.color(.brandPrimary) : theme.color(.textPrimary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from library" : "Add to library")
        .task { await store.refreshIfNeeded() }
        .libraryRemovalConfirmation(isPresented: $isConfirmingRemoval, title: title) { toggle() }
    }

    private func toggle() {
        Task {
            if await store.toggle(type, id: itemID) == .failed {
                toastCenter.show(String(localized: "Could not update your library, please try again"))
            }
        }
    }
}

extension View {
    /// `showConfirmationDialog('Remove from Library', …)` — one definition for
    /// every entry point that can remove a saved item.
    func libraryRemovalConfirmation(
        isPresented: Binding<Bool>,
        title: String?,
        onConfirm: @escaping () -> Void
    ) -> some View {
        let name = title?.trimmingCharacters(in: .whitespaces) ?? ""
        return confirmationDialog(
            name.isEmpty ? String(localized: "Remove this from your library?") : String(localized: "Remove \"\(name)\" from your library?"),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        }
    }
}
