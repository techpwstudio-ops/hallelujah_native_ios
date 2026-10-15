import SwiftUI
import Observation

/// `ProgressSpinner` — the 32pt white spinner Flutter uses for page loads.
struct HomeSpinner: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(Color.white)
            .frame(width: 32, height: 32)
    }
}

/// `Empty` — centred w600 text with 16 padding.
struct HomeEmptyText: View {
    let text: String

    var body: some View {
        Text(text)
            .typography(Typography.bodyMedium)
            .fontWeight(.semibold)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(Dimens.paddingLarge)
            .frame(maxWidth: .infinity)
    }
}

/// Scroll offset of a hero page, shared between the hero image, the fading
/// toolbar title and the collapsed-bar backdrop. Observed only by the small
/// views that read `offset`, so scrolling does not re-render the page body.
@MainActor
@Observable
final class HomeScrollState {
    var offset: CGFloat = 0

    func update(_ value: CGFloat) {
        if abs(value - offset) >= 0.5 { offset = value }
    }
}

private struct HomeHeroOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The `SliverAppBar` hero: a square, full-width image with `parallax` collapse
/// (moves at half the scroll speed), stretching on overscroll, with the
/// `GradiantDecoratedBox` scrim (`black @ 0.7` fading to clear over the top 32%
/// and from clear back to `black @ 0.7` over the bottom 32%).
struct HomeHeroHeader: View {
    let url: URL?
    let width: CGFloat
    let state: HomeScrollState
    var showTopGradient = true
    var showBottomGradient = true

    static let space = "homeHeroScroll"

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named(Self.space)).minY
            let stretch = max(0, minY)
            let parallax = minY < 0 ? -minY * 0.5 : 0
            ZStack {
                ArtworkView(
                    url: url,
                    width: width,
                    height: width + stretch,
                    cornerRadius: 0
                )
                scrim
            }
            .frame(width: width, height: width + stretch)
            .offset(y: parallax - stretch)
            .preference(key: HomeHeroOffsetKey.self, value: -minY)
        }
        .frame(width: width, height: width)
        .clipped()
        .onPreferenceChange(HomeHeroOffsetKey.self) { value in
            MainActor.assumeIsolated { state.update(value) }
        }
    }

    @ViewBuilder
    private var scrim: some View {
        let top = Color.black.opacity(0.7)
        if showTopGradient && showBottomGradient {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: top, location: 0.0),
                    Gradient.Stop(color: .clear, location: 0.32),
                    Gradient.Stop(color: .clear, location: 0.68),
                    Gradient.Stop(color: top, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if showBottomGradient {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: .clear, location: 0.65),
                    Gradient.Stop(color: top, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if showTopGradient {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: top, location: 0.0),
                    Gradient.Stop(color: .clear, location: 0.35),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// The pinned toolbar title that fades in as the hero collapses. `fade` maps
/// the scroll offset to an opacity: a ramp (see-all pages: 8 -> 72) or a
/// 200ms threshold switch (album pages: past `expanded - toolbar - 40`).
struct HomeFadingTitle: View {
    let title: String
    let state: HomeScrollState
    let opacity: (CGFloat) -> Double
    var animated = false
    var weight: Font.Weight?

    var body: some View {
        Text(title)
            .typography(Typography.titleMedium)
            .fontWeight(weight)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .opacity(opacity(state.offset))
            .animation(animated ? .easeInOut(duration: 0.2) : nil, value: opacity(state.offset))
    }
}

/// The pinned bar turns solid black once the hero has scrolled away
/// (`SliverAppBar(backgroundColor: black, pinned: true)`).
struct HomeCollapsedBarBackdrop: View {
    let state: HomeScrollState
    let threshold: CGFloat

    var body: some View {
        Color.black
            .opacity(state.offset > threshold ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: state.offset > threshold)
            .frame(height: 140)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
    }
}

/// `ShuffleWidget` — a 48pt disc (white @ 6%) holding the shuffle glyph, grey
/// when off and white when on. The Dart icon is the `shuffle.svg` asset; the SF
/// Symbol stands in until that asset is bundled.
struct HomeShuffleButton: View {
    @State private var queueController: QueueController = DependencyContainer.current.resolve()

    var body: some View {
        Button {
            Task { await queueController.toggleShuffle() }
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(queueController.isShuffled ? Color.white : Color.gray)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Footer spinner row (`Padding(vertical: 16, child: ProgressSpinner)`).
struct HomePageLoadingRow: View {
    var body: some View {
        HomeSpinner()
            .padding(.vertical, Dimens.paddingLarge)
            .frame(maxWidth: .infinity)
    }
}

/// `SongListItem` -> `MusicListItem` / `EpisodeListItem` over
/// `BaseMediaListTile`: 12/8 padding; 56pt thumbnail (16:9 wide for episodes,
/// radius 4, `sm`); 14 gap; a one-line capitalised titleMedium w600 title
/// (bold yellow for the song that is currently active); music shows its genre
/// (bodySmall white70), an episode its duration, plus a two-line description
/// (white60) and the release date (white54) below. Trailing: the shared song
/// menu button. Tapping plays the list as `source`.
struct HomeSongListRow: View {
    let song: Song
    let songs: [Song]
    let source: QueueAttribution
    var userPlaylistID: String?

    @Environment(AppNavigationCoordinator.self) private var coordinator

    /// `Vx.yellow500` (0xFFFFEB3B).
    private static let activeColor = Color(red: 0xFF / 255, green: 0xEB / 255, blue: 0x3B / 255)

    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    var body: some View {
        let isActive = HomePlayback.shared.isCurrent(songID: song.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(
                    url: HomeArt.url(song.displayImage, song.displayImageVariants, .sm),
                    width: Dimens.listItemThumbnailSizeMd * CGFloat(song.displayAspectRatio),
                    height: Dimens.listItemThumbnailSizeMd,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
                Color.clear.frame(width: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text((song.title ?? "").homeCapitalized)
                        .typography(Typography.titleMedium)
                        .fontWeight(isActive ? .bold : .semibold)
                        .foregroundStyle(isActive ? Self.activeColor : Color.white)
                        .lineLimit(1)
                    Text(song.isEpisode ? HomeFormat.durationText(song.duration) : (song.primaryGenre?.name ?? ""))
                        .typography(Typography.bodySmall)
                        .foregroundStyle(HomeColors.white70)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SongMenuButton(song: song, userPlaylistID: userPlaylistID)
            }
            if song.isEpisode {
                Color.clear.frame(height: 12)
                Text(song.description ?? "")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(HomeColors.white60)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Color.clear.frame(height: 6)
                Text(song.releaseDate.map { Self.dateFormatter.string(from: $0) } ?? "")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(HomeColors.white50)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            HomePlayback.shared.play(song: song, in: songs, source: source, coordinator: coordinator)
        }
    }
}

extension View {
    /// Hosts a hero page's `NavigationStack` chrome: a transparent bar over the
    /// image, light content, and the fading title.
    func homeHeroChrome<Title: View>(@ViewBuilder title: () -> Title) -> some View {
        self
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { title() }
            }
    }
}
