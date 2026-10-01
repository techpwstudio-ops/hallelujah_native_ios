import SwiftUI

/// T37 — ports `QueuePage` (`lib/views/player/queue_page.dart`), replacing
/// `FullScreenDestinationView`'s `PlayerRoute.queue` placeholder. Reached
/// from `FullPlayerView`'s (T35) queue button, already pushing this route.
///
/// Dart presents this as a `DraggableScrollableSheet` (a bottom sheet with
/// its own drag handle); T35 already decided the native queue entry point
/// is an ordinary push onto `PlayerRoute`'s stack instead — "one
/// presentation mechanism for that destination rather than two competing
/// ones" (`FullPlayerView`'s own doc comment) — so this screen is a plain
/// pushed view with system nav-bar chrome, no `DragHandler`/sheet sizing to
/// port.
///
/// Shows the FULL queue (past and future), not just what's upcoming,
/// matching Dart's own `audioHandler.fullLogicalQueueSongIds` — highlighting
/// rather than hiding whatever's already played, exactly as `queue_page
/// .dart:100-114`'s `isCurrentSong` styling does.
struct QueueView: View {
    @Environment(\.appTheme) private var theme
    @State private var queueController: QueueController = DependencyContainer.current.resolve()

    private var songs: [Song] { queueController.queue?.songs ?? [] }
    private var currentIndex: Int? { queueController.queue?.currentIndex }

    var body: some View {
        Group {
            if songs.isEmpty {
                EmptyStateView(title: "Queue is empty")
            } else {
                List {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        QueueSongRow(song: song, isCurrent: index == currentIndex)
                            .listRowBackground(
                                index == currentIndex
                                    ? theme.color(.textPrimary).opacity(0.08)
                                    : Color.clear
                            )
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await queueController.jump(to: index) }
                            }
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                // Always-visible trailing drag handles, matching Dart's own
                // per-row `ReorderableDragStartListener`/`MenuIcon` (always
                // shown, not gated behind an Edit toggle Dart has no
                // equivalent of).
                .environment(\.editMode, .constant(.active))
            }
        }
        .background(theme.color(.backgroundPrimary).ignoresSafeArea())
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `ReorderQueueItemPlayerEvent(oldIndex, newIndex)`
    /// (`queue_page.dart:90-96`) takes a single already-resolved index
    /// pair; SwiftUI's `.onMove` instead hands back an `IndexSet` (a drag
    /// only ever populates one) plus a `destination` expressed as an
    /// insertion point in the PRE-removal array — converted to the single
    /// post-removal target index `QueueController.reorder(from:to:)`
    /// expects via the standard `move(fromOffsets:toOffset:)` arithmetic.
    private func move(from source: IndexSet, to destination: Int) {
        guard source.count == 1, let oldIndex = source.first else { return }
        let newIndex = oldIndex < destination ? destination - 1 : destination
        guard newIndex != oldIndex else { return }
        Task { await queueController.reorder(from: oldIndex, to: newIndex) }
    }
}
