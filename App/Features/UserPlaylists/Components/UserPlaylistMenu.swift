import SwiftUI

/// Which user playlist a row's "more" button opened the menu for.
struct UserPlaylistMenuTarget: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// The playlist's cover, for the share card until the share endpoint's
    /// own image arrives.
    var artworkURL: URL? = nil
}

extension View {
    /// `showUserPlaylistMenu(context, playlist)` (`lib/sheets/custom_playlist.dart`):
    /// "Add to queue" for everyone; "Edit playlist" and "Delete Playlist"
    /// (confirmed with Dart's exact message) for the owner. `onDeleted` runs
    /// after a successful delete so the host list can refresh. Also "Share
    /// playlist" for everyone, "Make Private"/"Make Public" for the owner and
    /// "Add to library"/"Remove from library" (confirmed on removal) for
    /// everyone else. `onChanged` fires after a follow change (a visibility
    /// change is posted as `userPlaylistVisibilityDidChange` instead);
    /// `onUnfollowed` after a successful unfollow (the detail page pops).
    func userPlaylistMenu(
        target: Binding<UserPlaylistMenuTarget?>,
        onDeleted: (() -> Void)? = nil,
        onChanged: (() -> Void)? = nil,
        onUnfollowed: (() -> Void)? = nil
    ) -> some View {
        modifier(UserPlaylistMenuPresenter(target: target, onDeleted: onDeleted, onChanged: onChanged, onUnfollowed: onUnfollowed))
    }
}

private struct UserPlaylistMenuPresenter: ViewModifier {
    @Binding var target: UserPlaylistMenuTarget?
    let onDeleted: (() -> Void)?
    let onChanged: (() -> Void)?
    let onUnfollowed: (() -> Void)?

    @State private var pendingDelete: UserPlaylistMenuTarget?
    @State private var pendingUnfollow: UserPlaylistMenuTarget?
    @State private var detent: PresentationDetent = .medium
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    private var isPresented: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var isConfirmingUnfollow: Binding<Bool> {
        Binding(get: { pendingUnfollow != nil }, set: { if !$0 { pendingUnfollow = nil } })
    }

    func body(content: Content) -> some View {
        content
            .libraryRemovalConfirmation(isPresented: isConfirmingUnfollow, title: pendingUnfollow?.title) {
                guard let pending = pendingUnfollow else { return }
                pendingUnfollow = nil
                Task { await runFollowToggle(for: pending) }
            }
            .appSheet(isPresented: isPresented, detents: [.medium, .large], selection: $detent) {
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
                        },
                        // The menu swaps to the share card in place
                        // (`ShareService.sharePlaylist`'s share sheet), at
                        // full height so the card isn't cut off.
                        onShare: { detent = .large },
                        // The sheet closes at once; the new state shows
                        // straight away (optimistic), the toast follows the
                        // server's answer.
                        onVisibilityTapped: { actions in
                            self.target = nil
                            Task {
                                let text = await actions.toggleVisibility()
                                if !text.isEmpty { toastCenter.show(text) }
                            }
                        },
                        onFollowTapped: { isFollowing in
                            self.target = nil
                            if isFollowing {
                                pendingUnfollow = target
                            } else {
                                Task { await runFollowToggle(for: target) }
                            }
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
            .onChange(of: target == nil) { _, closed in
                if closed { detent = .medium }
            }
    }
}

extension UserPlaylistMenuPresenter {
    /// `toggleFollowUserPlaylist` + its toast; a successful unfollow also
    /// tells the host (the detail page leaves with the playlist).
    @MainActor
    fileprivate func runFollowToggle(for target: UserPlaylistMenuTarget) async {
        let viewModel = UserPlaylistActionsViewModel(playlistID: target.id)
        await viewModel.loadFollowState()
        switch await viewModel.toggleFollow() {
        case .followed(let message):
            toastCenter.show(message)
            onChanged?()
        case .unfollowed(let message):
            toastCenter.show(message)
            onChanged?()
            onUnfollowed?()
        case .failed(let message):
            toastCenter.show(message)
        }
    }
}

private struct UserPlaylistMenuSheet: View {
    let target: UserPlaylistMenuTarget
    @State private var viewModel: UserPlaylistMenuViewModel
    @State private var showsShare = false
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMessage: (String) -> Void
    let onShare: () -> Void
    let onVisibilityTapped: (UserPlaylistActionsViewModel) -> Void
    let onFollowTapped: (Bool) -> Void

    init(
        target: UserPlaylistMenuTarget,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onShare: @escaping () -> Void,
        onVisibilityTapped: @escaping (UserPlaylistActionsViewModel) -> Void,
        onFollowTapped: @escaping (Bool) -> Void
    ) {
        self.target = target
        _viewModel = State(initialValue: UserPlaylistMenuViewModel(playlistID: target.id, title: target.title))
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onMessage = onMessage
        self.onShare = onShare
        self.onVisibilityTapped = onVisibilityTapped
        self.onFollowTapped = onFollowTapped
    }

    var body: some View {
        if showsShare {
            ShareSheetView(
                target: .userPlaylist(id: target.id),
                title: target.title,
                subtitle: nil,
                artworkURL: target.artworkURL
            )
        } else {
            menu
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            SongMenuRow(systemImage: "text.badge.plus", title: "Add to queue") {
                Task { onMessage(await viewModel.addToQueue()) }
            }
            SongMenuRow(systemImage: "square.and.arrow.up", title: "Share playlist") {
                showsShare = true
                onShare()
            }
            if viewModel.isOwner {
                SongMenuRow(systemImage: "square.and.pencil", title: "Edit playlist") { onEdit() }
                SongMenuRow(
                    systemImage: viewModel.actions.isPublic ? "globe" : "lock.fill",
                    title: LocalizedStringKey(viewModel.actions.visibilityTitle)
                ) {
                    onVisibilityTapped(viewModel.actions)
                }
                // Reopened before the last toggle's answer: wait for it.
                .disabled(viewModel.actions.isTogglingVisibility)
                .opacity(viewModel.actions.isTogglingVisibility ? 0.5 : 1)
                SongMenuRow(systemImage: "xmark", title: "Delete Playlist") { onDelete() }
            } else if viewModel.isLoaded {
                SongMenuRow(
                    systemImage: viewModel.actions.isFollowing ? "bookmark.slash" : "bookmark",
                    title: viewModel.actions.isFollowing ? "Remove from library" : "Add to library"
                ) {
                    onFollowTapped(viewModel.actions.isFollowing)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .task { await viewModel.load() }
    }
}
