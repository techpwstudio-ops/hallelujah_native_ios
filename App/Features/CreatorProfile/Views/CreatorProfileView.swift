import SwiftUI
import UIKit

/// Ports `CreatorSongsPage` (`lib/views/library/creator_songs_page.dart`): a
/// square full-bleed hero (extends under the status bar, scrimmed by
/// `GradiantDecoratedBox`, a "more" button top-right opening the creator
/// menu), the info block (name `headlineSmall`; "<n> Followers" in 70% white
/// beside a 36pt Follow/Following pill; Shuffle + Play on the right for song
/// tabs), a pinned scrollable tab bar (Songs / Albums / Podcasts / Seasons,
/// white underline, `labelLarge`) and the active tab's list (8pt padding) —
/// `SongListItem` rows for song tabs, `PlaylistListItem` rows for albums /
/// seasons. Spinner while loading; "Something went wrong" on failure.
///
/// The hero collapses like `FlexibleSpaceBar` (`CollapseMode.parallax`): the
/// image scrolls at half speed inside its clipped frame and the creator's name
/// fades into the black app bar once it has gone. Not ported: the `Hero`
/// thumbnail transition.
struct CreatorProfileView: View {
    @State private var viewModel: CreatorProfileViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var menuTarget: ContentMenuTarget?
    @State private var showsCollapsedTitle = false
    @State private var tabBarMinY: CGFloat = .greatestFiniteMagnitude
    /// Top edge of the hero in the scroll's space (0 at rest, negative once
    /// scrolled); drives the parallax.
    @State private var heroMinY: CGFloat = 0

    @Environment(AppNavigationCoordinator.self) private var coordinator

    init(creatorId: String) {
        _viewModel = State(initialValue: CreatorProfileViewModel(creatorId: creatorId))
    }

    /// `AppRoute.creatorSongs(creatorID:userPlaylistID:)`.
    init(creatorID: String?, userPlaylistID: String? = nil) {
        _viewModel = State(initialValue: CreatorProfileViewModel(creatorId: creatorID ?? ""))
    }

    var body: some View {
        Group {
            if let creator = viewModel.creator {
                scroll(creator: creator)
            } else if viewModel.isLoadingCreator {
                ParitySpinner(fills: true).frame(maxHeight: .infinity)
            } else if viewModel.loadError != nil {
                ParityEmptyText(text: "Something went wrong").frame(maxHeight: .infinity)
            } else {
                ParitySpinner(fills: true).frame(maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .top)
        .appNavigationBarBackground(isVisible: showsCollapsedTitle)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
        .toolbar {
            if let creator = viewModel.creator {
                ToolbarItem(placement: .principal) {
                    Text(creator.name ?? "")
                        .font(.custom(Typography.fontFamily, size: 16).weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .opacity(showsCollapsedTitle ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showsCollapsedTitle)
                }
            }
            if viewModel.creator != nil {
                moreToolbarItem
            }
        }
        .task { await viewModel.onAppear() }
        .contentMenu(target: $menuTarget) {
            // The menu can follow/unfollow; refresh so the header chip agrees.
            Task { await viewModel.loadCreator() }
        }
    }

    /// On iOS 26 the shared toolbar glass stretched the 48pt tap target into a
    /// pill beside the round back button, so the button draws its own 44pt
    /// glass circle to match it.
    @ToolbarContentBuilder
    private var moreToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                ParityIconButton(systemName: "ellipsis", rotation: 90, size: 20, tooltip: "More", hitSize: 44) {
                    openCreatorMenu()
                }
                .glassCircle(interactive: true)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                ParityIconButton(systemName: "ellipsis", rotation: 90, tooltip: "More") { openCreatorMenu() }
            }
        }
    }

    private func openCreatorMenu() {
        if let creator = viewModel.creator { menuTarget = .creator(creator) }
    }

    /// Bottom edge of the (collapsed) app bar: status-bar inset + toolbar.
    private var appBarBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let top = scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
        return top + 44
    }

    /// The `SliverPersistentHeader(pinned: true)` tab bar has reached the app bar.
    private var isTabBarPinned: Bool { tabBarMinY < appBarBottom }

    private func scroll(creator: Creator) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Square frame; the image inside moves down by half the scroll
                // distance so it appears to scroll at half speed. No top scrim:
                // it darkened the top third of the photo, and the glass back /
                // more buttons stay legible without it.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ParityHeroImage(
                            url: ArtworkURLResolver().resolve(path: creator.image, variant: .lg, allowedVariants: creator.imageVariants, fallbackName: creator.name),
                            aspect: 1,
                            stops: []
                        )
                        .offset(y: heroMinY < 0 ? -heroMinY * 0.5 : 0)
                    }
                    // Fade the hero into the page so it doesn't end on a hard
                    // edge right above the name. Pinned to the frame, not the
                    // parallaxing image, so it stays put while scrolling.
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [Color.black.opacity(0), Color.black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 96)
                            .allowsHitTesting(false)
                    }
                    .clipped()
                    .background(
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .named("creatorScroll"))
                            Color.clear
                                .preference(key: CreatorHeroMaxYKey.self, value: frame.maxY)
                                .preference(key: CreatorHeroMinYKey.self, value: frame.minY)
                        }
                    )

                info(creator: creator)

                if !viewModel.tabs.isEmpty {
                    tabBar
                        .opacity(isTabBarPinned ? 0 : 1)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CreatorTabBarMinYKey.self,
                                    value: proxy.frame(in: .named("creatorScroll")).minY
                                )
                            }
                        )
                }

                // Rows carry their own 12pt inset; this lines their artwork up
                // with the name and the tab label (16pt).
                tabContent
                    .padding(.vertical, Dimens.screenPaddingAll)
                    .padding(.horizontal, Dimens.screenPaddingAll * 2 - Dimens.paddingMedium)
                Color.clear.frame(height: 16)
            }
        }
        .coordinateSpace(name: "creatorScroll")
        .heroScrollEdgeEffect(isCollapsed: showsCollapsedTitle)
        .onPreferenceChange(CreatorHeroMaxYKey.self) { maxY in
            let shouldShow = maxY < 150
            if shouldShow != showsCollapsedTitle { showsCollapsedTitle = shouldShow }
        }
        .onPreferenceChange(CreatorHeroMinYKey.self) { minY in
            if abs(minY - heroMinY) > 0.5 { heroMinY = minY }
        }
        .onPreferenceChange(CreatorTabBarMinYKey.self) { minY in
            if minY != tabBarMinY { tabBarMinY = minY }
        }
        .overlay(alignment: .top) {
            // Pinned copy of the tab bar, parked just under the app bar.
            if isTabBarPinned, !viewModel.tabs.isEmpty {
                tabBar.padding(.top, appBarBottom)
            }
        }
    }

    // MARK: - Info

    private func info(creator: Creator) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(creator.name ?? "")
                    .typography(ParityHeroText.headlineSmall)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                Spacer().frame(height: 8)
                HStack(spacing: 8) {
                    Text(HomeFormat.followerCountText(creator.followersCount))
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(ParityColor.white70)
                    followButton(creator: creator)
                }
            }
            Spacer(minLength: 0)
            if case .songs? = viewModel.selectedTab {
                HStack(spacing: 8) {
                    ParityShuffleButton(isOn: queueController.isShuffled) {
                        Task { await queueController.toggleShuffle() }
                    }
                    ParityPlayPauseButton(isPlaying: isPlaying) { togglePlayback() }
                }
            }
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 2)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    /// `CreatorFollowButton`: a 36pt `ElevatedButton`, label w600 white.
    private func followButton(creator: Creator) -> some View {
        Button {
            Task { await viewModel.toggleFollow() }
        } label: {
            Text(creator.isFollowing == true ? "Following" : "Follow")
                .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                .foregroundStyle(creator.isFollowing == true ? Color.white : Color.black)
                .padding(.horizontal, 24)
                .frame(height: 36)
                .glassCapsule(creator.isFollowing == true ? .regular : .tinted(.brandPrimary), interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTogglingFollow)
    }

    // MARK: - Tabs

    /// `TabBar(isScrollable, tabAlignment: start, indicatorColor: white)`:
    /// Material 3's label-width indicator (3pt, rounded top) over a
    /// full-width hairline divider.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.tabs, id: \.self) { tab in
                    let isSelected = viewModel.selectedTab == tab
                    Button {
                        viewModel.selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .typography(Typography.labelLarge)
                            .foregroundStyle(isSelected ? Color.white : Color(red: 0xCA / 255, green: 0xC4 / 255, blue: 0xD0 / 255))
                            .frame(height: 48)
                            .overlay(alignment: .bottom) {
                                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                    .fill(isSelected ? Color.white : Color.clear)
                                    .frame(height: 3)
                            }
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 48)
        .background(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .songs(let type)?:
            songsList(type: type)
        case .playlists(let type)?:
            playlistsList(type: type)
        case nil:
            EmptyView()
        }
    }

    private func songsList(type: HomeContentType) -> some View {
        let songs = viewModel.songs(for: type)
        return VStack(spacing: 0) {
            if songs.isEmpty, viewModel.isLoadingSongs(for: type) || !viewModel.hasLoadedSongs(for: type) {
                ParitySpinner(fills: true)
            } else if songs.isEmpty {
                ParityEmptyText(text: "No Record Founds.")
            } else {
                ForEach(songs) { song in
                    CreatorSongRow(song: song) { play(song: song, in: songs) }
                        .task { await viewModel.loadMoreSongsIfNeeded(type: type, currentItem: song) }
                }
                if viewModel.isLoadingSongs(for: type) {
                    ParitySpinner()
                }
            }
        }
        .task(id: type) { await viewModel.loadSongsIfNeeded(type: type) }
    }

    private func playlistsList(type: HomeContentType) -> some View {
        let playlists = viewModel.playlists(for: type)
        return VStack(spacing: 0) {
            if playlists.isEmpty, viewModel.isLoadingPlaylists(for: type) || !viewModel.hasLoadedPlaylists(for: type) {
                ParitySpinner(fills: true)
            } else if playlists.isEmpty {
                ParityEmptyText(text: "No Record Founds.")
            } else {
                ForEach(playlists) { playlist in
                    CreatorPlaylistRow(playlist: playlist, contentType: type) { open(playlist) }
                        .task { await viewModel.loadMorePlaylistsIfNeeded(type: type, currentItem: playlist) }
                }
                if viewModel.isLoadingPlaylists(for: type) {
                    ParitySpinner()
                }
            }
        }
        .task(id: type) { await viewModel.loadPlaylistsIfNeeded(type: type) }
    }

    // MARK: - Actions

    private func open(_ playlist: Playlist) {
        var creatorID: String?
        var creatorName: String?
        if case let .creator(id, name) = playlist.owner {
            creatorID = id
            creatorName = name
        }
        coordinator.push(.playlistDetail(
            playlistID: playlist.id,
            title: playlist.title,
            image: playlist.image,
            imageVariants: playlist.imageVariants,
            songsCount: playlist.songsCount,
            isCompanyOwned: playlist.owner == .company,
            creatorID: creatorID,
            creatorName: creatorName
        ))
    }

    private var attribution: QueueAttribution {
        QueueAttribution(playerType: .creator, id: viewModel.creator?.creatorId, title: viewModel.creator?.name ?? "")
    }

    private var currentSongs: [Song] {
        if case .songs(let type)? = viewModel.selectedTab { return viewModel.songs(for: type) }
        return []
    }

    private var isThisQueueActive: Bool {
        queueController.queue?.source.playerID == attribution.playerID
    }

    private var isPlaying: Bool {
        isThisQueueActive && audioEngine.status == .playing
    }

    private func togglePlayback() {
        if isThisQueueActive {
            if audioEngine.status == .playing { audioEngine.pause() } else { audioEngine.resume() }
            return
        }
        guard let first = currentSongs.first else { return }
        play(song: first, in: currentSongs)
    }

    private func play(song: Song, in songs: [Song]) {
        if isThisQueueActive, queueController.queue?.currentSong?.id == song.id {
            if audioEngine.status == .playing { audioEngine.pause() } else { audioEngine.resume() }
            return
        }
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        let source = attribution
        Task {
            await queueController.play(songs: songs, startIndex: index, source: source)
            coordinator.presentPlayer()
        }
    }
}

private extension View {
    /// iOS 26 blurs and dims scroll content under the navigation bar, which
    /// smeared the top of the hero at rest. Keep that edge effect only once
    /// the hero has collapsed and rows scroll under the bar.
    @ViewBuilder
    func heroScrollEdgeEffect(isCollapsed: Bool) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(!isCollapsed, for: .top)
        } else {
            self
        }
    }
}

private struct CreatorHeroMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CreatorTabBarMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CreatorHeroMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
