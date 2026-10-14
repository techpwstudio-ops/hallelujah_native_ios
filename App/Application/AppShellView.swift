import SwiftUI

/// The "signed in" app shell — five independent per-tab `NavigationStack`s
/// under one `TabView`, plus the full-screen presentations
/// (`FullScreenDestination`) that sit above all of them. `RootView` shows
/// this for `LaunchDestination.app`.
///
/// The system `TabView` chrome is hidden (`.toolbar(.hidden, for: .tabBar)`)
/// in favor of `AppBottomDockView` (T17) — the "Glass UI" non-negotiable
/// requires the tab bar to go through `GlassSurface` like every other raised
/// surface, so it's a custom overlay rather than the system bar, even though
/// `.tabItem`/`.tag` still drive `TabView`'s own selection/state-preservation
/// machinery underneath. Every tab's root content is a placeholder — nothing
/// here builds a real feature screen, only somewhere for one to eventually
/// be pushed to and popped from.
struct AppShellView: View {
    @State private var coordinator = AppNavigationCoordinator()
    @State private var networkStatus = NetworkStatusStore()
    // T38 — `_applyBackgroundSuspendFlow`'s `audioHandler.savePlaybackState()`
    // call site: the one place `AudioEngine.persistPlaybackPosition()` needs
    // to fire from. Resolved the same way `AppBottomDockView` already does,
    // not constructed fresh — this must be the SAME engine instance every
    // other player surface reads.
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    // T35 — shared between the mini player (`AppBottomDockView`) and the
    // full player (`FullScreenDestinationView`'s `.player` case) so the
    // latter's zoom transition can originate from the former's exact frame.
    @Namespace private var playerTransitionNamespace

    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $coordinator.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack(path: coordinator.path(for: tab)) {
                        TabRootView(tab: tab)
                            .navigationDestination(for: AppRoute.self) { route in
                                AppRouteDestinationView(route: route)
                            }
                    }
                    .tabItem {
                        Label {
                            Text(tab.titleKey)
                        } icon: {
                            theme.icon(tab.icon)
                        }
                    }
                    .tag(tab)
                }
            }
            .toolbar(.hidden, for: .tabBar)

            AppBottomDockView(playerTransitionNamespace: playerTransitionNamespace)
        }
        .environment(coordinator)
        .environment(networkStatus)
        // T18 — this is the earliest point a coordinator exists to route a
        // deep link to; DeepLinkService buffers anything that arrived before
        // this fires (cold launch racing the splash/auth flow) and dispatches
        // it here instead of dropping it.
        .onAppear { DeepLinkService.shared.attach(coordinator: coordinator) }
        .onDisappear { DeepLinkService.shared.detach() }
        // T66 — same "earliest point a coordinator exists" reasoning as
        // `DeepLinkService`'s own attach/detach immediately above.
        .onAppear {
            PushNotificationService.shared.activate()
            PushNotificationRouter.shared.attach(coordinator: coordinator)
        }
        .onDisappear { PushNotificationRouter.shared.detach() }
        // T19 — `InternetService.instance.init()`/`suspend()`/`resume()`
        // (`lib/views/launch/launch_app.dart`) run from `LaunchApp`, the Dart
        // route that is this shell's real counterpart (mounted post-auth,
        // hosting the tab-bar scaffold via `OurAdaptiveScaffold`) — not from
        // the splash (`FlashScreen`, already T15's concern). Started here for
        // the same "earliest point a signed-in shell exists" reason
        // DeepLinkService attaches here.
        .onAppear { networkStatus.start() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: networkStatus.resume()
            case .background:
                networkStatus.suspend()
                audioEngine.persistPlaybackPosition()
            default: break
            }
        }
        .fullScreenCover(item: $coordinator.presentedFullScreen) { destination in
            FullScreenDestinationView(destination: destination, playerTransitionNamespace: playerTransitionNamespace)
                .environment(coordinator)
        }
    }
}

/// No `NavigationStack` of its own — it's placed as the root content of the
/// per-tab `NavigationStack` already created in `AppShellView.body`.
/// Nesting a second one here would give this tab its own separate
/// navigation bar/environment instead of sharing that outer stack's.
///
/// T28/T42/T43 — `.home`, `.search`, and `.library` now render their real
/// screens instead of the shared placeholder every other still-unbuilt tab
/// uses.
private struct TabRootView: View {
    let tab: AppTab

    var body: some View {
        // The banner now lives inside Home's scroll content (Flutter mounts
        // it as the first sliver of `home_screen.dart`).
        content
            .navigationTitle(Text(tab.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            // Home draws its own profile header; Flutter has no app bar there.
            .toolbar(tab == .home ? .hidden : .automatic, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView()
        case .search:
            BrowseView()
        case .aiAssistant:
            AIChatHomeView()
        case .library:
            LibraryHomeView()
        case .read:
            ReaderView()
        default:
            EmptyStateView(icon: tab.icon, title: String(localized: tab.titleKey))
        }
    }
}

private struct AppRouteDestinationView: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        if screenSetsOwnTitle {
            content
        } else {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// D12: the screens ported to the Flutter look draw their own app bar /
    /// title, so the shell must not add a second one. Only the screens still
    /// using generic chrome (or the placeholder) get the shell's title.
    private var screenSetsOwnTitle: Bool {
        switch route {
        case .storageSettings, .contentLanguage, .creatorGrid, .cropCompressImage: false
        default: true
        }
    }

    /// T40/T42/T43/T44/T46 — the cases with a real screen to dispatch to;
    /// every other still-unbuilt route keeps the shared placeholder.
    @ViewBuilder
    private var content: some View {
        switch route {
        case let .downloads(type):
            DownloadsView(type: type)
        case .storageSettings:
            StorageSettingsView()
        case .contentSearch:
            ContentSearchView()
        case let .seeAllSongs(type, _, image, imageVariants, _, uniqueIDWithType, label, _, dataID):
            SeeAllSongsView(
                type: type, image: image, imageVariants: imageVariants,
                uniqueID: uniqueIDWithType ?? dataID, label: label
            )
        case let .seeAllArtists(type, title, dataID, _):
            SeeAllArtistsView(type: type, title: title, uiId: dataID)
        case .recentSongs:
            RecentSongsView(type: .all)
        case let .creatorSongs(creatorID, userPlaylistID):
            CreatorProfileView(creatorID: creatorID, userPlaylistID: userPlaylistID)
        case .episodes:
            EpisodesView()
        case .genreSearch:
            GenreSearchView()
        case let .genreSongs(genreID, genreName, genreImage, genreImageVariants):
            GenreSongsView(
                genreID: genreID,
                genreName: genreName,
                genreImage: genreImage,
                genreImageVariants: genreImageVariants
            )
        case let .playlistDetail(playlistID, title, image, imageVariants, songsCount, isCompanyOwned, creatorID, creatorName):
            PlaylistDetailView(playlist: Playlist(
                id: playlistID,
                title: title,
                description: nil,
                image: image,
                imageVariants: imageVariants,
                type: nil,
                visibility: nil,
                language: nil,
                songsCount: songsCount,
                duration: nil,
                rank: nil,
                owner: isCompanyOwned ? .company : .creator(id: creatorID, name: creatorName),
                createdAt: nil,
                updatedAt: nil,
                isSeed: false
            ))
        case let .favouriteSongs(type, label, _):
            FavouriteSongsView(type: type, label: label)
        case let .favouriteArtists(songType):
            FavouriteArtistsView(songType: songType)
        case let .createPlaylist(userPlaylistID, _, songID):
            CreatePlaylistView(userPlaylistID: userPlaylistID, songID: songID)
        case let .userPlaylistSongs(playlistID):
            UserPlaylistDetailView(playlistID: playlistID)
        case let .bibleVerseShare(verseReference, verseText, deepLinkURL):
            BibleVerseShareView(verseReference: verseReference, verseText: verseText, deepLinkURL: deepLinkURL)
        case .notificationSettings:
            NotificationSettingsView()
        case .helpSupportDashboard:
            HelpView()
        case .faqs:
            FAQView()
        case .feedback:
            FeedbackView()
        case .deleteAccount:
            AccountDeletionView()
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        case .aiHistory:
            AIChatHistoryView()
        case let .aiChat(conversationID, initialMessage):
            AIChatDetailView(conversationID: conversationID, initialMessage: initialMessage)
        case .subscriptionPlans:
            SubscriptionPlansView()
        case .manageFamilyMembers:
            ManageFamilyMembersView()
        default:
            EmptyStateView(title: route.placeholderTitle)
        }
    }

    /// `.genreSongs`/`.playlistDetail`/`.favouriteSongs` carry their real
    /// name inline (T42/T43/T44) — shown in the nav bar instead of the
    /// generic placeholder when present. `.favouriteArtists` has no carried
    /// display name, so it correctly falls through to `placeholderTitle`'s
    /// "Favourite Artists".
    private var navigationTitle: String {
        if case let .genreSongs(_, genreName, _, _) = route, let genreName, !genreName.isEmpty {
            return genreName
        }
        if case let .playlistDetail(_, title, _, _, _, _, _, _) = route, !title.isEmpty {
            return title
        }
        if case let .favouriteSongs(_, label, _) = route, !label.isEmpty {
            return label
        }
        if case let .createPlaylist(userPlaylistID, _, _) = route {
            return userPlaylistID == nil ? "Create Playlist" : "Edit Playlist"
        }
        return route.placeholderTitle
    }
}

private struct FullScreenDestinationView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    let destination: FullScreenDestination
    let playerTransitionNamespace: Namespace.ID

    var body: some View {
        NavigationStack(path: playerPathBinding) {
            destinationRoot
                .navigationDestination(for: PlayerRoute.self) { route in
                    playerRouteDestination(route)
                }
        }
    }

    /// T36/T37 — both `PlayerRoute` cases now render their real screens.
    @ViewBuilder
    private func playerRouteDestination(_ route: PlayerRoute) -> some View {
        switch route {
        case .queue:
            QueueView()
        case let .lyrics(songTitle):
            SongLyricsView(songTitle: songTitle)
        }
    }

    /// T35/T59 — `.player` and `.aiAudioConversation` now render their real
    /// screens; `.aiVoiceOverlay` is still pending its own future task and
    /// keeps the original placeholder.
    @ViewBuilder
    private var destinationRoot: some View {
        switch destination {
        case .player:
            FullPlayerView()
                .navigationTransition(.zoom(sourceID: MiniPlayerDockView.transitionID, in: playerTransitionNamespace))
        case let .aiAudioConversation(conversationID):
            VoiceConversationScreen(conversationID: conversationID)
        case .aiVoiceOverlay:
            EmptyStateView(
                title: destination.placeholderTitle,
                actionTitle: "Dismiss",
                action: { coordinator.dismissFullScreen() }
            )
        }
    }

    /// Only the player presentation has an internal path — `.aiVoiceOverlay`/
    /// `.aiAudioConversation` never push a `PlayerRoute` on top of
    /// themselves, so this is just an always-empty, unused path for those.
    private var playerPathBinding: Binding<[PlayerRoute]> {
        guard destination == .player else { return .constant([]) }
        return Binding(
            get: { coordinator.playerPath },
            set: { coordinator.playerPath = $0 }
        )
    }
}

private extension AppRoute {
    var placeholderTitle: String {
        switch self {
        case .settings: "Settings"
        case .profile: "Profile"
        case .notificationSettings: "Notification Settings"
        case .subscriptionPlans: "Subscription Plans"
        case .manageFamilyMembers: "Manage Family Members"
        case .deleteAccount: "Delete Account"
        case .contentLanguage: "Content Language"
        case .helpSupportDashboard: "Help & Support"
        case .faqs: "FAQs"
        case .feedback: "Feedback"
        case .genreSearch: "Genre Search"
        case .episodes: "Episodes"
        case .contentSearch: "Content Search"
        case .aiHistory: "AI History"
        case .aiChat: "Chat"
        case .downloads: "Downloads"
        case .storageSettings: "Storage"
        case .createPlaylist: "Create Playlist"
        case .creatorGrid: "Creators"
        case .creatorSongs: "Creator Songs"
        case .userPlaylistSongs: "Playlist"
        case .playlistDetail: "Playlist"
        case .favouriteSongs: "Favourites"
        case .favouriteArtists: "Favourite Artists"
        case .genreSongs: "Genre"
        case .recentSongs: "Recent Songs"
        case .seeAllSongs: "Songs"
        case .seeAllArtists: "Artists"
        case .bibleVerseShare: "Share Verse"
        case .cropCompressImage: "Edit Photo"
        }
    }
}

private extension FullScreenDestination {
    var placeholderTitle: String {
        switch self {
        case .player: "Now Playing"
        case .aiVoiceOverlay: "Voice"
        case .aiAudioConversation: "Voice"
        }
    }
}

#Preview {
    AppShellView()
        .environment(\.appTheme, .standard)
}
