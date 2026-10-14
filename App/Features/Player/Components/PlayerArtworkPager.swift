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
/// **Not ported**: Dart's overscroll-past-the-queue-edge gesture (`>48pt`
/// past the first/last page dispatches `SeekToNextSongEvent`/
/// `SeekToPreviousSongEvent(allowRestart:false)`, letting a swipe run
/// past the queue's boundary into skipping tracks). `TabView(.page)`
/// exposes no rubber-band/overscroll-distance hook to build this against,
/// and a hand-rolled paging `DragGesture` replacement risks getting the
/// core swipe-to-scrub behavior wrong for a rarely-used edge nicety —
/// flagged as a deliberate scope cut, not an oversight.
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
