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
/// Not ported: the collapsing parallax app bar, its fade-in title and the
/// `Hero` thumbnail transition.
struct CreatorProfileView: View {
    @State private var viewModel: CreatorProfileViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var menuTarget: ContentMenuTarget?
    @State private var showsCollapsedTitle = false
    @State private var tabBarMinY: CGFloat = .greatestFiniteMagnitude

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
        .toolbarBackground(showsCollapsedTitle ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
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
                ToolbarItem(placement: .primaryAction) {
                    ParityIconButton(systemName: "ellipsis", rotation: 90, tooltip: "More") {
                        if let creator = viewModel.creator { menuTarget = .creator(creator) }
                    }
                }
            }
        }
        .task { await viewModel.onAppear() }
        .contentMenu(target: $menuTarget) {
            // The menu can follow/unfollow; refresh so the header chip agrees.
            Task { await viewModel.loadCreator() }
        }
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
                ParityHeroImage(
                    url: ArtworkURLResolver().resolve(path: creator.image, variant: .lg, allowedVariants: creator.imageVariants),
                    aspect: 1
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CreatorHeroMaxYKey.self,
                            value: proxy.frame(in: .named("creatorScroll")).maxY
                        )
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

                tabContent
                    .padding(Dimens.screenPaddingAll)
                Color.clear.frame(height: 16)
            }
        }
        .coordinateSpace(name: "creatorScroll")
        .onPreferenceChange(CreatorHeroMaxYKey.self) { maxY in
            let shouldShow = maxY < 150
            if shouldShow != showsCollapsedTitle { showsCollapsedTitle = shouldShow }
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
                Spacer().frame(height: 8)
                HStack(spacing: 8) {
                    Text("\(creator.followersCount ?? 0) Followers")
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

    /// `TabBar(isScrollable, tabAlignment: start, indicatorColor: white)`.
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
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(isSelected ? Color.white : Color.clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 48)
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
