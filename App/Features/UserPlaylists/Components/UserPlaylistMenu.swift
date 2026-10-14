import SwiftUI

/// Which user playlist a row's "more" button opened the menu for.
struct UserPlaylistMenuTarget: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

extension View {
    /// `showUserPlaylistMenu(context, playlist)` (`lib/sheets/custom_playlist.dart`):
    /// "Add to queue" for everyone; "Edit playlist" and "Delete Playlist"
    /// (confirmed with Dart's exact message) for the owner. `onDeleted` runs
    /// after a successful delete so the host list can refresh.
    func userPlaylistMenu(target: Binding<UserPlaylistMenuTarget?>, onDeleted: (() -> Void)? = nil) -> some View {
        modifier(UserPlaylistMenuPresenter(target: target, onDeleted: onDeleted))
    }
}

private struct UserPlaylistMenuPresenter: ViewModifier {
    @Binding var target: UserPlaylistMenuTarget?
    let onDeleted: (() -> Void)?

    @State private var pendingDelete: UserPlaylistMenuTarget?
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    private var isPresented: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    func body(content: Content) -> some View {
        content
            .appSheet(isPresented: isPresented, detents: [.medium]) {
                if let target {
                    UserPlaylistMenuSheet(
                        target: target,
                        onEdit: {
                            self.target = nil
                            coordinator.push(.createPlaylist(userPlaylistID: target.id, songType: nil, songID: nil))
                        },
                        onDelete: {
                            self.target = nil
                            pendingDelete = target
                        },
                        onMessage: { text in
                            self.target = nil
                            toastCenter.show(text)
                        }
                    )
                }
            }
            .confirmationDialog(
                "Do you really want to delete this playlist? Once deleted, it can't be restored.",
                isPresented: isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    guard let pending = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        let viewModel = UserPlaylistMenuViewModel(playlistID: pending.id, title: pending.title)
                        if await viewModel.delete() {
                            onDeleted?()
                        } else {
                            toastCenter.show("Network error")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

private struct UserPlaylistMenuSheet: View {
    @State private var viewModel: UserPlaylistMenuViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMessage: (String) -> Void

    init(
        target: UserPlaylistMenuTarget,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onMessage: @escaping (String) -> Void
    ) {
        _viewModel = State(initialValue: UserPlaylistMenuViewModel(playlistID: target.id, title: target.title))
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onMessage = onMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SongMenuRow(systemImage: "text.badge.plus", title: "Add to queue") {
                Task { onMessage(await viewModel.addToQueue()) }
            }
            if viewModel.isOwner {
                SongMenuRow(systemImage: "square.and.pencil", title: "Edit playlist") { onEdit() }
                SongMenuRow(systemImage: "xmark", title: "Delete Playlist") { onDelete() }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .task { await viewModel.load() }
    }
}
