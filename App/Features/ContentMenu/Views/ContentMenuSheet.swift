import SwiftUI

/// The overflow menu for a whole container (`showContentMenu` /
/// `showCreatorMenu`). One sheet for playlists, albums, seasons and artists:
/// every container offers the same things (queue it, share it, keep it) and
/// which rows appear is derived from the target, never from flags the caller
/// has to remember.
struct ContentMenuSheet: View {
    @State private var viewModel: ContentMenuViewModel
    @State private var showsShare = false
    @State private var isConfirmingRemoval = false
    @State private var store: LibrarySavedStore = DependencyContainer.current.resolve()
    let onOutcome: (ContentMenuOutcome) -> Void

    @Environment(\.appTheme) private var theme

    init(target: ContentMenuTarget, onOutcome: @escaping (ContentMenuOutcome) -> Void) {
        _viewModel = State(initialValue: ContentMenuViewModel(target: target))
        self.onOutcome = onOutcome
    }

    private var isSaved: Bool {
        switch viewModel.target {
        case .playlist: viewModel.target.libraryItem.map { store.isSaved($0.type, id: $0.id) } ?? false
        case .creator: viewModel.isFollowing
        }
    }

    var body: some View {
        if showsShare, let shareTarget = viewModel.target.shareTarget {
            ShareSheetView(
                target: shareTarget,
                title: viewModel.target.title,
                subtitle: nil,
                artworkURL: viewModel.target.artworkURL
            )
        } else {
            menu
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.canQueue {
                SongMenuRow(systemImage: "text.badge.plus", title: "Add to queue") {
                    Task { onOutcome(await viewModel.addToQueue()) }
                }
            }
            if viewModel.target.shareTarget != nil {
                SongMenuRow(
                    systemImage: "square.and.arrow.up",
                    title: shareTitle
                ) { showsShare = true }
            }
            if showsLibraryRow {
                SongMenuRow(
                    systemImage: isSaved ? "minus.circle" : "plus.circle",
                    title: isSaved ? "Remove from library" : "Add to library"
                ) { libraryTapped() }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .libraryRemovalConfirmation(isPresented: $isConfirmingRemoval, title: viewModel.target.title) { toggleLibrary() }
        .task { await store.refreshIfNeeded() }
    }

    private var shareTitle: LocalizedStringKey {
        if case .playlist = viewModel.target { return "Share playlist" }
        return "Share"
    }

    private var showsLibraryRow: Bool {
        switch viewModel.target {
        case .playlist: viewModel.target.libraryItem != nil
        case .creator: viewModel.target.shareTarget != nil
        }
    }

    private func libraryTapped() {
        if isSaved { isConfirmingRemoval = true } else { toggleLibrary() }
    }

    private func toggleLibrary() {
        Task {
            switch viewModel.target {
            case .playlist:
                guard let item = viewModel.target.libraryItem else { return }
                let result = await store.toggle(item.type, id: item.id)
                onOutcome(result == .failed ? .message(String(localized: "Could not update your library, please try again")) : .dismiss)
            case .creator:
                onOutcome(await viewModel.toggleFollow())
            }
        }
    }
}

extension View {
    /// Presents the container menu for `target` (set it to show, it resets to
    /// `nil` on dismissal) and toasts whatever the chosen action reports.
    func contentMenu(target: Binding<ContentMenuTarget?>, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ContentMenuPresenter(target: target, onDismiss: onDismiss))
    }
}

private struct ContentMenuPresenter: ViewModifier {
    @Binding var target: ContentMenuTarget?
    let onDismiss: (() -> Void)?
    @Environment(\.toastCenter) private var toastCenter

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: {
                guard !$0 else { return }
                target = nil
                onDismiss?()
            }
        )
    }

    func body(content: Content) -> some View {
        content.appSheet(isPresented: isPresented, detents: [.medium]) {
            if let target {
                ContentMenuSheet(target: target) { outcome in
                    if case .message(let text) = outcome { toastCenter.show(text) }
                    self.target = nil
                    onDismiss?()
                }
            }
        }
    }
}
