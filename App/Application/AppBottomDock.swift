import SwiftUI
import UIKit

/// The floating glass dock T17 adds above `AppShellView`'s (T16) plain
/// system `TabView` chrome. The "Glass UI" non-negotiable in `progress.md`
/// requires every raised surface — tab bar included — to go through
/// `GlassSurface`, so this replaces the system tab bar entirely rather than
/// reskinning it; `AppShellView` hides the native bar
/// (`.toolbar(.hidden, for: .tabBar)`) and overlays this instead. That also
/// sidesteps a real finding from research: iOS 26's system `TabView` already
/// renders as native Liquid Glass for free, but the non-negotiable applies
/// regardless of OS version, so a hand-built pill is required either way.
///
/// Two independent floating pills stacked vertically — `MusicPlayerBottomIos26`
/// and `_AnimatedNavBar` (`lib/widgets/navigation/our_adaptive_scaffold.dart`)
/// are genuinely separate widgets in Dart too, not one merged shape, each
/// animating in/out on its own. Both stay mounted at all times and animate via
/// opacity/offset rather than conditional insertion — Dart's own comment on
/// `MusicPlayerBottomIos26` warns against conditionally mounting/unmounting
/// this ("that would cause the liquid-glass pill to flash on route changes").
struct AppBottomDockView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var isKeyboardVisible = false
    // T34 — captured shared instances (T31/T33's own `AppComposition`
    // registrations), resolved once here rather than inside
    // `MiniPlayerDockView` itself so the dock is the one place that bridges
    // playback state to `AppNavigationCoordinator`, matching the pattern
    // `RootView` already established for `SignOutSignal`.
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    // T44 — resolved here (not inside `MiniPlayerDockView`) for the same
    // "dock is the one bridging point" reasoning as `audioEngine`/
    // `queueController` above.
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    // `MiniPlayerAdSlot`'s two ad sources (`AdPacingController`'s break,
    // `PlayerAdController`'s image takeover), resolved here for the same
    // "dock is the one bridging point" reasoning as above.
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var playerAd: PlayerAdController = DependencyContainer.current.resolve()
    // T35 — shared with `FullScreenDestinationView`'s `.player` presentation
    // via `AppShellView`, letting the full player's `.navigationTransition(
    // .zoom(...))` originate from this exact pill's on-screen frame.
    let playerTransitionNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Rides above the pill, inset to the same margin, and only where
            // the mini player is shown (`MiniPlayerAdSlot`), so a break the
            // listener has backed out of still says so wherever they went.
            if coordinator.isMiniPlayerVisible {
                MiniPlayerAdSlot(pacing: adPacing, playerAd: playerAd)
            }
            MiniPlayerDockView(
                isVisible: coordinator.isMiniPlayerVisible,
                engine: audioEngine,
                queueController: queueController,
                favouriteRepository: favouriteRepository,
                namespace: playerTransitionNamespace,
                onExpand: { coordinator.presentPlayer() }
            )
            GlassTabBarView(
                selectedTab: coordinator.selectedTab,
                isVisible: coordinator.isTabBarVisible && !isKeyboardVisible,
                onSelect: { tab in
                    if tab == coordinator.selectedTab {
                        coordinator.popToRoot(in: tab)
                    } else {
                        coordinator.selectedTab = tab
                    }
                }
            )
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.dockBottomInset)
        // Hides the tab bar (not the mini player — Dart doesn't gate that on
        // the keyboard either) while a text field's keyboard is up: the
        // floating pill sits over the body rather than pushing it up the way
        // `Scaffold.bottomNavigationBar` would, so leaving it up parks it on
        // top of the keyboard's accessory row (`our_adaptive_scaffold.dart`,
        // `_Ios26BodyWrapper`'s comment). No screen with a text field is
        // reachable from inside the shell yet, so this can't be exercised
        // today, but it costs nothing to wire now against the day one is.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        // T34 — `AppNavigationCoordinator.isPlaybackActive`'s own doc
        // comment named this exact task as the one that starts flipping it;
        // mirrors `DashboardNavBloc._canShowPlayer`'s own trigger
        // (`PlayerVisibilityChangedEvent`, fired whenever `songId` goes
        // nil<->non-nil).
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
            VStack(spacing: 0) {
                contentRow
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .frame(maxHeight: .infinity)
                progressHairline
            }
            .frame(height: Spacing.miniPlayerHeight)
        }
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

    /// `song_progress_bar.dart`'s mini-player (`preview: true`) path:
    /// `LinearProgressIndicator(minHeight: 2)`, white over `fillColor @ 0.8`;
    /// not scrubbable. Last child of the pill's `VStack`, clipped by the
    /// glass shape.
    private var progressHairline: some View {
        PlayerProgressLine(progress: progressFraction)
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
                theme.icon(tab.icon)
                    .font(.system(size: 22))
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
