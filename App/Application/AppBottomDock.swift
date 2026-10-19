import SwiftUI
import UIKit

/// The mini player (and its ad strip) as a bottom safe-area inset above the
/// system tab bar. The tab bar itself is the system `TabView` bar (Liquid
/// Glass on iOS 26); this only hosts the floating mini player pill, shown per
/// `canShowMusicPlayerBottom` (`coordinator.isMiniPlayerVisible`).
struct MiniPlayerInsetView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var playerAd: PlayerAdController = DependencyContainer.current.resolve()
    /// Shared with `FullScreenDestinationView`'s `.player` presentation, so
    /// the full player's zoom transition originates from this pill's frame.
    let playerTransitionNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if coordinator.isMiniPlayerVisible {
                MiniPlayerAdSlot(pacing: adPacing, playerAd: playerAd)
                MiniPlayerDockView(
                    isVisible: true,
                    engine: audioEngine,
                    queueController: queueController,
                    favouriteRepository: favouriteRepository,
                    namespace: playerTransitionNamespace,
                    onExpand: { coordinator.presentPlayer() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.lg)
        // One gap everywhere in the dock: ad strip <-> pill (the VStack
        // spacing above) and pill <-> tab bar are both `Spacing.sm`.
        .padding(.bottom, coordinator.isMiniPlayerVisible ? Spacing.sm : 0)
        .animation(MotionCurve.dockShow, value: coordinator.isMiniPlayerVisible)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { coordinator.dockInsetHeight = $0 }
        // `DashboardNavBloc._canShowPlayer`: playback present <-> player shown.
        .onChange(of: audioEngine.currentSong) { _, newValue in
            coordinator.isPlaybackActive = (newValue != nil)
        }
    }
}

/// T34 — `MusicPlayerBottomIos26`'s floating pill (`lib/widgets/player/
/// music_player_bottom_ios26.dart`), the ONE mini player design this native
/// rewrite builds — Dart ships a second, non-glass variant
/// (`MusicPlayerBottom`) purely for iOS-before-26/Android backward
/// compatibility (`GlassSurface`'s own doc comment already cites this same
/// split); this rewrite's minimum-deployment-target is a native-project
/// decision on its own terms, not a per-widget compatibility fork, so only
/// the glass design is ported.
///
/// Controls shown here are play/pause plus (T44) a favourite heart toggle,
/// matching Dart's own `_Controls` row (`music_player_bottom_ios26.dart:
/// 300-376`): `FavouriteButton(size: 20, color: white@0.85)` sits before
/// `PlayPauseIcon` in Dart's row, so here it's placed right after the
/// title/subtitle stack, before `outputRouteButton` — Dart's row has no
/// AirPlay button at all, that's a T39-only native addition with no Dart
/// slot to stay consistent with.
struct MiniPlayerDockView: View {
    @Environment(\.appTheme) private var theme
    let isVisible: Bool
    let engine: AudioEngine
    let queueController: QueueController
    let favouriteRepository: any FavouriteRepository
    let namespace: Namespace.ID
    let onExpand: () -> Void

    /// Shared with `FullScreenDestinationView`'s `.player` case so both
    /// halves of the zoom transition agree on the same source id.
    static let transitionID = "miniPlayer"

    /// `swipe_to_skip.dart`'s `_commitDistance` (44pt) — the distance half
    /// of its two-way commit test (`_commitDistance`/`_commitVelocity`, one
    /// OR the other). SwiftUI's `DragGesture` doesn't expose Flutter's raw
    /// px/s gesture velocity, so the flick half below is an adaptation, not
    /// a literal port — see its own doc comment.
    private static let commitDistance: CGFloat = 44
    /// Adapts `_commitVelocity` (220px/s, a flick too fast/short to cross
    /// `commitDistance` on its own) via `DragGesture.Value.predictedEndTranslation`
    /// — SwiftUI's own built-in extrapolation of where the gesture would
    /// end if it kept decelerating at its current velocity, the closest
    /// native equivalent to "was this fast enough to count as a flick"
    /// without hand-rolling velocity tracking. Reuses `swipe_to_skip.dart`'s
    /// own `_elasticStart` (88pt) as the threshold, since that's the same
    /// "how far a real flick's momentum reaches" ballpark Dart chose there,
    /// not a value invented for this file.
    private static let commitFlickDistance: CGFloat = 88
    private static let contentHorizontalPadding: CGFloat = 14 // music_player_bottom_ios26.dart:216-217
    private static let artworkSize: CGFloat = 44
    private static let progressLineWidth: CGFloat = 2 // song_progress_bar.dart `minHeight: 2`
    private static let musicArtworkCornerRadius: CGFloat = 12 // music_player_bottom_ios26.dart `_Artwork`: 12 music / 6 episode
    private static let episodeArtworkCornerRadius: CGFloat = 6
    private static let titleTypography = TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.4, tracking: -0.2)
    /// `_SongMeta` colours: title white, subtitle white @ 60%.
    private static let subtitleColor = Color.white.opacity(0.6)
    private static let textLineHeight: CGFloat = 18 // music_player_bottom_ios26.dart:312 MyMarquee(height: 18, ...)

    private var song: Song? { engine.currentSong }
    private var isPlaying: Bool { engine.status == .playing }

    private var subtitle: String {
        let parts = [song?.primaryArtists, song?.featuredArtists]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    private var progressFraction: Double {
        guard let duration = engine.currentItemDuration, duration > 0 else { return 0 }
        return min(1, max(0, engine.currentPosition / duration))
    }

    private var resolvedArtwork: URL? {
        guard let song else { return nil }
        return ArtworkURLResolver().resolve(path: song.displayImage, variant: .md, allowedVariants: song.displayImageVariants)
    }

    var body: some View {
        GlassSurface(.regular, cornerRadius: Radius.full) {
            contentRow
                .padding(.horizontal, Self.contentHorizontalPadding)
                .frame(height: Spacing.miniPlayerHeight)
        }
        // Outside the glass so it is drawn over the glass edge, not inside it.
        .overlay { progressBorder }
        .opacity(isVisible ? 1 : 0)
        // `SlideTransition` (0,1) -> 0 plus `ScaleTransition` 0.92 -> 1.0
        // anchored at the bottom centre, 380 ms out / 260 ms back.
        .scaleEffect(isVisible ? 1 : 0.92, anchor: .bottom)
        .offset(y: isVisible ? 0 : Spacing.miniPlayerHeight)
        .animation(isVisible ? MotionCurve.dockShow : MotionCurve.dockHide, value: isVisible)
        .contentShape(Rectangle())
        // `swipe_to_skip.dart:183-196`'s single gesture-arena doc comment —
        // one recognizer resolving both, rather than nested detectors.
        .onTapGesture { onExpand() }
        .gesture(swipeGesture)
        // Must be the LAST hit-test modifier: placed before `.onTapGesture`/
        // `.gesture` it only disabled the pill's children, leaving the hidden
        // (opacity 0) frame still tappable and opening the player.
        .allowsHitTesting(isVisible)
        // T35 — written against the iOS 18 zoom-navigation-transition API
        // as documented (Apple's own WWDC24 demos pair this exact
        // `matchedTransitionSource`/`.navigationTransition(.zoom(...))`
        // combination with a `.sheet` presentation for a "tap a small
        // element, it expands into a full-screen view" interaction,
        // structurally identical to this pill -> `FullPlayerView`); not
        // confirmed against `.fullScreenCover` specifically without a
        // build, same "flag on first real build" posture `GlassSurface`'s
        // own Q1 doc comment already established for its iOS 26 Glass API
        // surface.
        .playerZoomSource(id: Self.transitionID, in: namespace)
    }

    private var isEpisode: Bool { song?.isEpisode ?? false }
    private var artworkCornerRadius: CGFloat { isEpisode ? Self.episodeArtworkCornerRadius : Self.musicArtworkCornerRadius }

    /// `_Artwork`: 44pt high, 44 wide for music / 44 * 16/9 for an episode.
    private var contentRow: some View {
        HStack(spacing: 0) {
            ArtworkView(
                url: resolvedArtwork,
                width: isEpisode ? Self.artworkSize * 16 / 9 : Self.artworkSize,
                height: Self.artworkSize,
                cornerRadius: artworkCornerRadius
            )
            .overlay {
                RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: song?.title ?? "", typography: Self.titleTypography, color: Color.white, height: Self.textLineHeight)
                MarqueeText(text: subtitle, typography: Typography.bodySmall, color: Self.subtitleColor, height: Self.textLineHeight)
            }
            .padding(.leading, 12)

            Spacer(minLength: 0)

            favouriteButton
            Spacer().frame(width: 10)
            playPauseButton
            Spacer().frame(width: 8)
        }
    }

    /// `FavouriteButton(song:, color: Colors.white.withValues(alpha: 0.85),
    /// size: 20)` (`music_player_bottom_ios26.dart:300-376`'s `_Controls`).
    /// Optimistic: flips `engine.currentSong` immediately (so this button
    /// and the full player's stay in sync without waiting on the network),
    /// reverting only if the request actually fails.
    @ViewBuilder
    private var favouriteButton: some View {
        if let song {
            FavouriteToggleButton(
                isFavorited: song.isFavorited,
                size: 20,
                color: Color.white.opacity(0.85)
            ) {
                let target = !song.isFavorited
                engine.setCurrentSongFavorited(target, songId: song.id)
                do {
                    try await favouriteRepository.toggleSongFavorite(songId: song.id, isFavorited: target)
                } catch {
                    engine.setCurrentSongFavorited(!target, songId: song.id)
                }
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            if isPlaying { engine.pause() } else { engine.resume() }
        } label: {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 1.25)
                theme.icon(isPlaying ? .pause : .play)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }

    /// `song_progress_bar.dart`'s mini-player (`preview: true`) indicator, not
    /// scrubbable. Runs along the pill's bottom border — same corner radius
    /// as the glass, left end to right end — in white over a faint track of
    /// that same border (the same `white @ 0.12` as the artwork's stroke).
    private var progressBorder: some View {
        ZStack {
            PlayerProgressBottomBorder(progress: 1, cornerRadius: Radius.full, inset: Self.progressLineWidth / 2)
                .stroke(Color.white.opacity(0.12), lineWidth: Self.progressLineWidth)
            PlayerProgressBottomBorder(progress: progressFraction, cornerRadius: Radius.full, inset: Self.progressLineWidth / 2)
                .stroke(PlayerStyle.white, style: StrokeStyle(lineWidth: Self.progressLineWidth, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    /// Horizontal-only (`swipe_to_skip.dart` has no vertical drag/dismiss).
    /// Deliberately no visual feedback while dragging — the ios26 pill
    /// passes `slide: false` in Dart specifically because a transform or
    /// opacity change layered above a glass/backdrop-filter surface forces
    /// it to resample its backdrop every frame of the gesture ("the one
    /// thing that must not happen 120 times a second," `swipe_to_skip.dart:38-49`),
    /// so this only decides commit-or-not at the end of the gesture, same
    /// as that variant's own behavior.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let distance = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let committedByDistance = abs(distance) > Self.commitDistance
                let committedByFlick = abs(predicted) > Self.commitFlickDistance
                guard committedByDistance || committedByFlick else { return }
                let isForwardSwipe = committedByDistance ? distance < 0 : predicted < 0
                Task {
                    if isForwardSwipe {
                        await queueController.skipToNext()
                    } else {
                        await queueController.skipToPrevious(allowRestart: false)
                    }
                }
            }
    }
}

/// `_AnimatedNavBar` / `BottomNavBar` (`our_adaptive_scaffold.dart`,
/// `bottom_nav_bar.dart`) — icon plus an 11pt label per item
/// (`Typography.labelSmall`, an exact match for Dart's `fontSize: 11`).
/// Selected/unselected colors ground in `dashboard.dart`'s literal
/// `activeColor = Colors.white` / `inactiveColor = Colors.grey` — not the
/// brand color — so mapped to `textPrimary`/`textSecondary` rather than a
/// brand token.
struct GlassTabBarView: View {
    @Environment(\.appTheme) private var theme
    let selectedTab: AppTab
    let isVisible: Bool
    let onSelect: (AppTab) -> Void

    var body: some View {
        GlassSurface(.regular, cornerRadius: Radius.full) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .buttonStyle(.plain)
            .frame(height: Spacing.tabBarHeight)
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : Spacing.tabBarHeight)
        .animation(isVisible ? MotionCurve.dockShow : MotionCurve.dockHide, value: isVisible)
        .allowsHitTesting(isVisible)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: Spacing.xs) {
                theme.icon(tab.icon, size: 28)
                Text(tab.titleKey)
                    .typography(Typography.labelSmall)
            }
            .foregroundStyle(isSelected ? Color.white : Color(white: 0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            // iOS 26's native `UITabBar` (what Flutter embeds) lights the
            // selected item with a capsule inside the glass.
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(Color.white.opacity(0.12))
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Preview-only: shows both pills forced visible, since
/// `AppNavigationCoordinator.isPlaybackActive` defaulting to `false` means
/// `AppBottomDockView` itself never actually renders the mini player today.
/// Resolves the same DI-registered `AudioEngine`/`QueueController` the real
/// dock uses (`RootView`'s own `#Preview` block already establishes that
/// `DependencyContainer.current` is populated for previews the same as for
/// a real launch) rather than faking a `Song` — with no active playback
/// session, this renders the pill's honest empty state (blank artwork,
/// empty marquees, paused glyph, 0% progress), which still exercises the
/// real layout/glass container/show-hide animation, same as this preview's
/// pre-T34 placeholder content did.
private struct DockPreviewContent: View {
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @Namespace private var playerTransitionNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [ColorToken.backgroundPrimary.color, ColorToken.backgroundSecondary.color],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                MiniPlayerDockView(
                    isVisible: true,
                    engine: audioEngine,
                    queueController: queueController,
                    favouriteRepository: favouriteRepository,
                    namespace: playerTransitionNamespace,
                    onExpand: {}
                )
                GlassTabBarView(selectedTab: .home, isVisible: true, onSelect: { _ in })
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.dockBottomInset)
        }
    }
}

#Preview("Dock — visible, light") {
    DockPreviewContent()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dock — visible, dark") {
    DockPreviewContent()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}

/// Trailing breathing room at the end of a tab's scroll content. The dock's
/// own height is NOT included here — that comes from `dockClearanceInset()`,
/// applied once to every tab root and pushed screen in `AppShellView`.
struct DockClearance: View {
    var base: CGFloat = 24

    var body: some View {
        Color.clear.frame(height: base)
    }
}

/// Keeps a screen's content clear of the floating ad strip + mini player.
/// The mini player is a bottom safe-area inset on each tab's `NavigationStack`,
/// but that inset doesn't reach the screens inside the stack (the last row of
/// a pushed Settings page ended up under the pill), so each screen re-applies
/// it as its own inset, sized from the dock's measured height. Scroll views
/// get it as content inset; fixed layouts shrink above the dock. A `Spacing.sm`
/// gap separates content from the dock; nothing is added while the dock is
/// hidden (no playback, a sheet open, or a route that hides the mini player).
private struct DockClearanceInset: ViewModifier {
    @Environment(AppNavigationCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        let height = coordinator.dockInsetHeight
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: height > 0 ? height + Spacing.sm : 0)
        }
    }
}

extension View {
    func dockClearanceInset() -> some View {
        modifier(DockClearanceInset())
    }
}
