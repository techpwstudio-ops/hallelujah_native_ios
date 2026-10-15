import SwiftUI

/// T35 — ports `PlayerArtworkPager` (`lib/widgets/player/
/// player_artwork_pager.dart`): a swipeable carousel over the *whole
/// queue*, not just the current song's artwork. Square (1:1) for music,
/// 16:9 for an episode (`Song.displayAspectRatio`), sized to the
/// presenting screen's full width.
///
/// Dart distinguishes user-driven swipes from programmatic (bloc-driven)
/// page changes with an explicit flag to avoid an echo loop. This doesn't
/// need one: `selectionBinding` below is a computed `Binding` whose getter
/// always reflects `queueController`'s own ground truth
/// (`queue.currentSong.id`) and whose setter only calls `jump(to:)` when
/// the swiped-to id actually differs from it — swipe-driven and
/// externally-driven changes both flow through the same one-directional
/// "read ground truth, act only on a genuine difference" shape, so there's
/// nothing to echo.
///
/// Overscroll past the queue's edge (`_onScroll`): `TabView(.page)` exposes no
/// rubber-band distance, so a simultaneous `DragGesture` stands in — a pull
/// of more than 48pt towards "nothing there" while on the last / first page
/// dispatches `skipToNext()` / `skipToPrevious(allowRestart: false)`, the same
/// events the Next button and the Dart pager use, so the swipe reaches the
/// recommended-playlist hand-off identically.
struct PlayerArtworkPager: View {
    let queueController: QueueController

    /// `_Artwork` passes `radius: 0` and fills the full screen width — a
    /// square for music, 16:9 for episodes, edge to edge with no inset.
    private static let cornerRadius: CGFloat = 0

    private var songs: [Song] { queueController.queue?.songs ?? [] }
    private var currentSong: Song? { queueController.queue?.currentSong }

    var body: some View {
        TabView(selection: selectionBinding) {
            ForEach(songs) { song in
                GeometryReader { proxy in
                    ArtworkView(
                        url: resolvedArtwork(for: song),
                        width: proxy.size.width,
                        height: proxy.size.height,
                        cornerRadius: Self.cornerRadius
                    )
                }
                .tag(song.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Sizes the pager to the current song's aspect ratio at the
        // scroll view's full available width — an ordinary `.aspectRatio`
        // modifier on a `TabView`, which is expected to work the same as
        // on any other view, but this exact combination (`.page` style +
        // an outer `.aspectRatio`) has no precedent elsewhere in this
        // codebase to confirm against without a build; flag on the first
        // real one.
        .aspectRatio(currentSong?.displayAspectRatio ?? 1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .simultaneousGesture(edgeOverscrollGesture)
    }

    /// How far past the end the user has to pull for it to count as "next".
    static let overscrollThreshold: CGFloat = 48

    /// Pure decision behind the gesture, kept static for unit tests.
    /// `translation` is the drag's horizontal travel (negative = towards the
    /// next page). Returns `.next` / `.previous` only when the pull exceeds
    /// the threshold in the direction that has no page behind it.
    enum EdgeAction: Equatable { case next, previous }

    static func edgeAction(translation: CGFloat, index: Int, count: Int) -> EdgeAction? {
        guard count > 0, index >= 0 else { return nil }
        if index == count - 1, -translation > overscrollThreshold { return .next }
        if index == 0, translation > overscrollThreshold { return .previous }
        return nil
    }

    private var edgeOverscrollGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let index = queueController.queue?.currentIndex ?? 0
                switch Self.edgeAction(translation: value.translation.width, index: index, count: songs.count) {
                case .next:
                    Task { await queueController.skipToNext() }
                case .previous:
                    Task { await queueController.skipToPrevious(allowRestart: false) }
                case nil:
                    break
                }
            }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { currentSong?.id },
            set: { newID in
                guard let newID, newID != currentSong?.id,
                      let index = songs.firstIndex(where: { $0.id == newID })
                else { return }
                Task { await queueController.jump(to: index) }
            }
        )
    }

    private func resolvedArtwork(for song: Song) -> URL? {
        ArtworkURLResolver().resolve(path: song.displayImage, variant: .lg, allowedVariants: song.displayImageVariants)
    }
}
