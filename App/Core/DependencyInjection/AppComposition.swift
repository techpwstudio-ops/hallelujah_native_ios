import GRDB

/// The composition root: the one place real dependencies get registered.
/// `GHallelujahApp` calls `installRuntime()` once at launch; previews and
/// tests build their own small containers instead of touching this one.
enum AppComposition {
    /// `@MainActor` because `GHallelujahApp.init()` — its one caller — is
    /// itself main-actor-isolated (`SwiftUI.App`'s `init()` requirement),
    /// and T26's `SignOutSignal()` below needs that: it's a `@MainActor`
    /// `@Observable` type, constructed synchronously here rather than
    /// inside a View's `@State` default (the way every other `@Observable`
    /// view model in this app is), since it must be the SAME instance
    /// `session.setOnLogout`'s closure captures.
    @MainActor
    @discardableResult
    static func installRuntime(configuration: AppConfiguration = .current) -> DependencyContainer {
        // Must run before anything below touches Firebase (Crashlytics
        // included) — see FirebaseBootstrap's doc comment for the ordering
        // requirement this satisfies.
        FirebaseBootstrap.configure()

        let container = DependencyContainer()

        container.register(AppConfiguration.self) { configuration }
        container.register((any ClockProviding).self) { SystemClock() }
        // Q5 (progress.md Open questions), resolved: Crashlytics.
        container.register((any CrashReporting).self) { FirebaseCrashReporter() }
        container.register((any AppStoreVersionChecking).self) { ITunesAppStoreVersionChecker() }
        container.register((any AppTrackingTransparencyRequesting).self) { SystemAppTrackingTransparencyRequester() }
        // T19 — factory closure, not a captured shared instance like
        // `session`/`database` below: `NetworkStatusStore` resolves this once
        // per its own lifetime (`AppShellView`'s `@State`), and T38's
        // `PlaybackAnalyticsRecorder` below builds its own independent
        // instance directly (same construction, no shared state to
        // diverge) rather than resolving through the container — a fresh
        // instance per consumer is equivalent here and keeps this
        // registration consistent with its neighbors above.
        container.register((any ReachabilityMonitoring).self) { NWPathReachabilityMonitor(configuration: configuration) }

        // The refresh client deliberately has no authProvider: using the
        // authenticated client here would let a 401 from the refresh call
        // itself recurse back into Session.refreshIfNeeded().
        let tokenStore = KeychainTokenStore()
        let refreshClient = HTTPClient(configuration: configuration)
        let session = Session(tokenStore: tokenStore, refreshClient: refreshClient)
        container.register(Session.self) { session }
        container.register(HTTPClient.self) { HTTPClient(configuration: configuration, authProvider: session) }

        // T20 — `CurrentUserStore` is a captured shared instance, not a
        // per-resolve factory closure like `NetworkStatusStore` below: it's
        // written to from `RemoteAuthRepository` (this composition root, not
        // a View's `@State`), so every resolver needs the SAME actor, the
        // same reason `session`/`database` are captured `let`s rather than
        // built fresh inside their registration closures.
        let currentUserStore = CurrentUserStore(keyValueStore: UserDefaultsKeyValueStore())
        container.register(CurrentUserStore.self) { currentUserStore }
        // T61 — a captured shared instance, same reasoning as
        // `currentUserStore` immediately above: `RemoteAuthRepository`
        // writes to it on login/refresh/logout, and every resolver
        // (`SettingsView`, `SubscriptionPlansView`) must observe the SAME
        // actor, not an independent copy.
        let membershipStore = MembershipStore(keyValueStore: UserDefaultsKeyValueStore())
        container.register(MembershipStore.self) { membershipStore }
        // T65 — the one premium gate every feature check goes through.
        container.register(PremiumGate.self) { PremiumGate(membershipStore: membershipStore) }
        // T26 — the one place anything reacts to a session ending, for
        // whatever reason. Both registered actions run off this SAME
        // `onLogout` closure (a single-callback seam — see `SignOutSignal`'s
        // doc comment for why a future subsystem must extend this closure
        // rather than call `setOnLogout` again):
        let signOutSignal = SignOutSignal()
        container.register(SignOutSignal.self) { signOutSignal }
        // T67 — a captured shared instance, same reasoning as `currentUserStore`/
        // `signOutSignal` above: exactly one socket connection may exist, and
        // `session.setOnLogout`'s closure just below must disconnect the SAME
        // instance every event-consuming feature observes.
        let realtimeEventBus = RealtimeEventBus()
        container.register(RealtimeEventBus.self) { realtimeEventBus }
        let realtimeDispatcher = RealtimeEventDispatcher(currentUserStore: currentUserStore, eventBus: realtimeEventBus)
        let realtimeConnectionManager = RealtimeConnectionManager(
            configuration: configuration,
            authProvider: session,
            dispatcher: realtimeDispatcher
        )
        container.register(RealtimeConnectionManager.self) { realtimeConnectionManager }
        // T46 — constructed here, ahead of `audioEngine`/`queueController`
        // below (where every OTHER `DownloadEngine` reader resolves it
        // from), for one reason only: `session.setOnLogout`'s closure just
        // below must capture it directly, matching `currentUserStore`'s/
        // `signOutSignal`'s own capture-by-local-`let` shape immediately
        // above — a closure can't capture a local variable declared after
        // itself. Fatal on failure, same posture as `Database.makeDefault`
        // and the `DiskCache` registration further below: a downloads
        // directory that can't be created means downloads can't function.
        let downloadCatalogStore = try! DownloadCatalogStore()
        let downloadEngine = DownloadEngine(
            proxyBaseURL: configuration.proxyBaseURL,
            tokenProvider: session,
            catalogStore: downloadCatalogStore,
            client: HTTPClient(configuration: configuration, authProvider: session)
        )
        container.register(DownloadCatalogStore.self) { downloadCatalogStore }
        container.register(DownloadEngine.self) { downloadEngine }
        Task {
            await session.setOnLogout {
                // T24 — closes a gap `Session`'s own doc comment already
                // flagged: `refreshIfNeeded()` calls `logout()` internally
                // (refresh-token expiry) with no way to reach
                // `CurrentUserStore` itself, so without this the cached
                // `User` would silently outlive its session and
                // `SplashViewModel.resolveDestination()` could route on a
                // stale `needsAccountSetup`. Mirrors `RemoteAuthRepository`'s
                // own paired `session.logout()` + `currentUserStore.clear()`
                // calls, just reached from a path with no direct reference
                // to the store.
                Task { await currentUserStore.clear() }
                // T61 — same reasoning as `currentUserStore.clear()` just
                // above: a session ended from a path with no direct
                // reference to `RemoteAuthRepository.logout()` (refresh-
                // token expiry) must not leave a stale membership cached.
                Task { await membershipStore.clear() }
                // T26 — tells `RootView` to fall back to the sign-in flow
                // from wherever it currently is, matching `session.dart`'s
                // `NavigationService.offAll(AuthenticationPage.routeName)`.
                Task { @MainActor in signOutSignal.notify() }
                // T46 — a signed-out user's downloaded audio must not remain
                // accessible to whoever signs in next on a shared device.
                Task { @MainActor in downloadEngine.deleteAll() }
                // T67 — a signed-out user must stop receiving realtime events
                // scoped to their old session's rooms.
                Task { @MainActor in realtimeConnectionManager.disconnect() }
            }
        }
        // T15 already activated the App Check provider factory
        // (`GHallelujahAppCheckProviderFactory`, `FirebaseBootstrap.configure()`
        // above) — `FirebaseAppCheckProvider` just wraps the SDK call T20 needs.
        container.register((any AppCheckProviding).self) { FirebaseAppCheckProvider() }
        container.register((any AuthRepository).self) {
            RemoteAuthRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                session: session,
                currentUserStore: currentUserStore,
                membershipStore: membershipStore,
                appCheck: FirebaseAppCheckProvider(),
                configuration: configuration,
                realtimeConnectionManager: realtimeConnectionManager
            )
        }

        // T28 — `HomeFeedCache` is a captured shared instance (same
        // reasoning as `currentUserStore` above): `RemoteHomeRepository`
        // writes through it on every successful layout fetch, so every
        // resolver needs the same actor.
        let homeFeedCache = HomeFeedCache(keyValueStore: UserDefaultsKeyValueStore())
        container.register(HomeFeedCache.self) { homeFeedCache }
        container.register((any HomeRepository).self) {
            RemoteHomeRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                cache: homeFeedCache
            )
        }
        // T30 — no shared state to capture (unlike `homeFeedCache`/
        // `currentUserStore` above): a fresh `HTTPClient` per resolve is
        // equivalent, same reasoning as `ReachabilityMonitoring`'s
        // registration above.
        container.register((any CreatorRepository).self) {
            RemoteCreatorRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T29 — same "no shared state to capture" reasoning as
        // `CreatorRepository` above.
        container.register((any PlaylistRepository).self) {
            RemotePlaylistRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T40/T41 — same "no shared state to capture" reasoning as
        // `CreatorRepository`/`PlaylistRepository` above.
        container.register((any SearchRepository).self) {
            RemoteSearchRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T42 — same "no shared state to capture" reasoning as
        // `CreatorRepository`/`PlaylistRepository`/`SearchRepository` above.
        container.register((any GenreRepository).self) {
            RemoteGenreRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T43 — same "no shared state to capture" reasoning as
        // `CreatorRepository`/`PlaylistRepository`/`SearchRepository`/
        // `GenreRepository` above.
        container.register((any LibraryRepository).self) {
            RemoteLibraryRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T44 — same "no shared state to capture" reasoning as
        // `CreatorRepository`/`PlaylistRepository`/`SearchRepository`/
        // `GenreRepository`/`LibraryRepository` above.
        container.register((any FavouriteRepository).self) {
            RemoteFavouriteRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // Song menu — same "no shared state to capture" reasoning as above.
        container.register((any SongRepository).self) {
            RemoteSongRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T45 — same "no shared state to capture" reasoning as the
        // repositories above.
        container.register((any UserPlaylistRepository).self) {
            RemoteUserPlaylistRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T71 — same "no shared state to capture" reasoning as the
        // repositories above.
        container.register((any SupportRepository).self) {
            RemoteSupportRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        container.register((any AccountRepository).self) {
            RemoteAccountRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                session: session,
                currentUserStore: currentUserStore
            )
        }
        // T61 — same "no shared state to capture" reasoning as the
        // repositories above.
        container.register((any SubscriptionRepository).self) {
            RemoteSubscriptionRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T61 — a captured shared instance, same reasoning as
        // `realtimeConnectionManager`/`audioEngine` above: its own doc
        // comment requires exactly one `Transaction.updates` listener for
        // the app's whole lifetime, and every resolver must observe the
        // SAME `status`.
        let storeKitPurchaseManager = StoreKitPurchaseManager(
            subscriptionRepository: RemoteSubscriptionRepository(client: HTTPClient(configuration: configuration, authProvider: session)),
            membershipStore: membershipStore,
            keyValueStore: UserDefaultsKeyValueStore()
        )
        container.register(StoreKitPurchaseManager.self) { storeKitPurchaseManager }
        // T63 — same "no shared state to capture" reasoning as the
        // repositories above.
        container.register((any FamilyMembersRepository).self) {
            RemoteFamilyMembersRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T64 — same "no shared state to capture" reasoning as the other
        // repositories above.
        container.register((any TipRepository).self) {
            RemoteTipRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T64 — a captured shared instance, same reasoning as
        // `storeKitPurchaseManager` immediately above: its own doc comment
        // requires exactly one `Transaction.updates` listener for the app's
        // whole lifetime, and every resolver must observe the SAME `status`.
        let tipPurchaseManager = TipPurchaseManager(
            tipRepository: RemoteTipRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        )
        container.register(TipPurchaseManager.self) { tipPurchaseManager }
        // T66 — same "no shared state to capture" reasoning, except
        // `notificationPreferencesStore`, a captured shared instance for the
        // same reason `playlistProgressStore`/`recentSearchStore` are below:
        // every resolver must see the same in-memory opt-out state.
        container.register((any NotificationTopicsRepository).self) {
            RemoteNotificationTopicsRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        let notificationPreferencesStore = NotificationPreferencesStore(keyValueStore: UserDefaultsKeyValueStore())
        container.register(NotificationPreferencesStore.self) { notificationPreferencesStore }
        container.register(PushNotificationTokenRegistrar.self) {
            PushNotificationTokenRegistrar(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        // T58 — same "no shared state to capture" reasoning as the other
        // repositories above, except `AIChatNavigationStore`, a captured
        // shared instance for the same reason `notificationPreferencesStore`
        // above is: `AIChatHomeView`/`AIChatHistoryView` must observe the
        // same cross-screen signal.
        container.register((any AIChatRepository).self) {
            RemoteAIChatRepository(client: HTTPClient(configuration: configuration, authProvider: session))
        }
        container.register(AIChatStreamingClient.self) {
            AIChatStreamingClient(configuration: configuration, authProvider: session)
        }
        let aiChatNavigationStore = AIChatNavigationStore()
        container.register(AIChatNavigationStore.self) { aiChatNavigationStore }

        // T31 — a captured shared instance, same reasoning as `homeFeedCache`/
        // `currentUserStore`/`signOutSignal` above: exactly one `AVQueuePlayer`
        // may exist, and every future reader (mini player, full player, queue
        // screen, T32's Now Playing wiring) needs the SAME engine instance,
        // not an independent one per resolve. Constructed synchronously here
        // for the same reason `SignOutSignal()` is — `installRuntime()` is
        // already `@MainActor`, which `AudioEngine`'s own init requires.
        let userDefaultsStore = UserDefaultsKeyValueStore()
        let audioEngine = AudioEngine(
            proxyBaseURL: configuration.proxyBaseURL,
            keyValueStore: userDefaultsStore,
            batteryMonitor: UIDeviceBatteryLevelMonitor(),
            connectivityType: NWPathConnectivityTypeProvider(),
            tokenProvider: session
        )
        container.register(AudioEngine.self) { audioEngine }
        // T47 — local-file-first playback source: consulted at the top of
        // `AudioEngine.makePlayerItem(for:forceProxy:)` before any remote
        // resolution, so a downloaded (T46) song plays from disk instead.
        audioEngine.localFileURLProvider = { [downloadEngine] songID in
            downloadEngine.localFileURL(for: songID)
        }
        // T33 — a captured shared instance, same reasoning as `audioEngine`:
        // it's the one source of truth for the queue/source/shuffle/repeat
        // model, and every future reader (mini player, full player, queue
        // screen, T32's coordinator below) needs the SAME instance.
        let queueController = QueueController(engine: audioEngine, keyValueStore: userDefaultsStore)
        container.register(QueueController.self) { queueController }
        // T32 — registered (not just constructed) for the same reason
        // `audioEngine` above is: nothing else holds a strong reference to
        // it, and it must live for the app's whole lifetime for its
        // `MPRemoteCommandCenter` targets and `withObservationTracking`
        // registration to keep firing. Never resolved again by name — its
        // only job is OS-facing (lock screen/Control Center), no view model
        // needs it — but the container keeps it alive regardless. Takes
        // `queueController` too (T33) so lock-screen next/previous route
        // through the queue model's repeat-aware skip resolution rather
        // than `AudioEngine`'s own bare index±1 primitives.
        let nowPlayingCoordinator = NowPlayingCoordinator(engine: audioEngine, queueController: queueController, tokenProvider: session)
        container.register(NowPlayingCoordinator.self) { nowPlayingCoordinator }

        // T69 — a captured shared instance, same reasoning as `audioEngine`
        // above: `AdPacingController` subscribes to `audioEngine.onSongChanged`
        // for the app's whole lifetime, so every resolver (`FullPlayerView`)
        // must observe the SAME instance, not an independent copy with its
        // own cadence counter.
        let adsRepository = AdsRepository(
            client: HTTPClient(configuration: configuration, authProvider: session),
            membershipStore: membershipStore
        )
        container.register(AdsRepository.self) { adsRepository }
        // The sleep timer outlives the player screen, so it is one shared instance too.
        let sleepTimerController = SleepTimerController(engine: audioEngine)
        container.register(SleepTimerController.self) { sleepTimerController }
        let adPacingController = AdPacingController(adsRepository: adsRepository, engine: audioEngine)
        container.register(AdPacingController.self) { adPacingController }

        // Fatal on failure, same as the config/Info.plist parsing above: a
        // database or cache directory that can't be created means the app
        // can't function, so fail loudly at launch rather than limp along.
        var migrator = DatabaseMigrator()
        migrator.registerAnalyticsMigrations()
        // T54 — the Bible chapter/note local cache's own migration set.
        migrator.registerBibleMigrations()
        // T56 — the verse-of-day local cache's own migration set.
        migrator.registerVerseOfDayMigrations()
        let database = try! Database.makeDefault(migrator: migrator)
        container.register(Database.self) { database }
        // T54 — same "no shared state to capture" reasoning as the other
        // repositories above; needs `database` (for its local chapter/note
        // cache), so registered here rather than alongside them, after it.
        container.register((any BibleRepository).self) {
            RemoteBibleRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                database: database
            )
        }
        // T55 — same "no shared state to capture" reasoning as
        // `BibleRepository` above: the CDN snapshot fetch is a fully-
        // unauthenticated `URLSession` GET (see this type's own doc
        // comment), and `cdnHost` is the same static per-environment value
        // every other `configuration.*BaseURL` here reads directly, not the
        // `RemoteSettings.current.cdnUrl` indirection `ArtworkURLResolver`
        // uses for image URLs specifically.
        container.register((any BibleOfflineRepository).self) {
            RemoteBibleOfflineRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                cdnHost: configuration.cdnHost
            )
        }
        // T55 — a captured shared instance, same reasoning as
        // `playlistProgressStore`/`recentSearchStore` below:
        // `BibleOfflineDownloadButton` resolves this per view instance (one
        // per language row in `LanguagePickerSheet`'s list, all visible at
        // once), and every one of them must observe the SAME `status`/
        // `isLanguageDownloaded` state, not an independent copy. Its own
        // `BibleChapterCache(database:)` is a second instance from
        // `RemoteBibleRepository`'s internal one above, not the same
        // object — safe because both wrap the same `database.queue`
        // (GRDB's own serialized-access guarantee), the same reasoning
        // `Database.self`'s single registration already relies on.
        let bibleOfflineDownloadService = BibleOfflineDownloadService(
            bibleRepository: RemoteBibleRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                database: database
            ),
            offlineRepository: RemoteBibleOfflineRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                cdnHost: configuration.cdnHost
            ),
            chapterCache: BibleChapterCache(database: database),
            keyValueStore: userDefaultsStore
        )
        container.register(BibleOfflineDownloadService.self) { bibleOfflineDownloadService }
        // T55 — a captured shared instance, same "every resolver must see
        // the same in-memory `entries`" reasoning as `recentSearchStore`
        // below; a separate store because it's an unrelated feature with a
        // different persisted key/entry type, not because the pattern differs.
        let bibleRecentSearchStore = BibleRecentSearchStore(keyValueStore: userDefaultsStore, clock: SystemClock())
        container.register(BibleRecentSearchStore.self) { bibleRecentSearchStore }
        container.register((any KeyValueStoring).self) { UserDefaultsKeyValueStore() }
        container.register(DiskCache.self) { try! DiskCache(directoryName: "artwork") }

        // T56 — same "no shared state to capture" reasoning as
        // `BibleRepository`/`BibleOfflineRepository` above; needs `database`
        // (for `VerseOfDayCache`, its local last-delivered-verse mirror), so
        // registered here rather than alongside the stateless repositories
        // higher up.
        container.register((any VerseOfDayRepository).self) {
            RemoteVerseOfDayRepository(
                client: HTTPClient(configuration: configuration, authProvider: session),
                database: database
            )
        }
        // T56/T60 — a captured shared instance, same reasoning as
        // `aiChatNavigationStore` above: `ReaderView` and `VerseOfDayCardView`
        // (a verse tap on the Home card, or a push-notification/deep-link
        // landing) must all be able to hand the SAME reader screen a pending
        // book/chapter target, regardless of which one set it.
        let readerNavigationStore = ReaderNavigationStore()
        container.register(ReaderNavigationStore.self) { readerNavigationStore }

        let analyticsStore = AnalyticsEventStore(database: database)
        // T38 — the real `/analytics/track` contract: decodes the generic
        // queue back into `playbackSessions`/`playbackEvents` and posts them,
        // closing the gap this closure's own TODO used to flag.
        let analyticsUploader = PlaybackAnalyticsUploader(
            client: HTTPClient(configuration: configuration, authProvider: session),
            currentUserStore: currentUserStore
        )
        let analyticsEngine = AnalyticsSyncEngine(store: analyticsStore, clock: SystemClock()) { events, force in
            await analyticsUploader.upload(events, force: force)
        }
        let analyticsService = AnalyticsService(store: analyticsStore, engine: analyticsEngine)
        container.register((any AnalyticsTracking).self) { analyticsService }

        // T38 — a captured shared instance, same reasoning as `homeFeedCache`/
        // `currentUserStore` above: backs a future Home "Continue Your
        // Journey" rail, which needs the SAME store every `recordPlay` call
        // wrote to.
        let playlistProgressStore = PlaylistProgressStore(keyValueStore: userDefaultsStore)
        container.register(PlaylistProgressStore.self) { playlistProgressStore }

        // T40/T41 — a captured shared instance, same reasoning as
        // `playlistProgressStore` above: every resolver must see the same
        // in-memory `entries`, not an independent copy that could go stale
        // relative to a write another resolver just made. Deliberately NOT
        // added to `signOutSignal`'s closure above — see this store's own
        // doc comment for why sign-out must leave it untouched.
        let recentSearchStore = RecentSearchStore(keyValueStore: userDefaultsStore, clock: SystemClock())
        container.register(RecentSearchStore.self) { recentSearchStore }

        // T38 — registered (not just constructed), same reasoning as
        // `nowPlayingCoordinator` above: nothing else holds a strong
        // reference, and it must live for the app's whole lifetime for its
        // `withObservationTracking` registration and the `onSeek`/
        // `onLoopRestart` closures it installs on `audioEngine`/
        // `queueController` to keep firing. `AudioQualitySelector` is a
        // stateless dependency wrapper (no mutable state of its own beyond
        // what `userDefaultsStore` already owns), so building a second
        // instance here — rather than exposing `audioEngine`'s private one —
        // is equivalent, same reasoning already used for `ReachabilityMonitoring`'s
        // registration above.
        let playbackAnalyticsRecorder = PlaybackAnalyticsRecorder(
            engine: audioEngine,
            queueController: queueController,
            analytics: analyticsService,
            progressStore: playlistProgressStore,
            qualitySelector: AudioQualitySelector(
                keyValueStore: userDefaultsStore,
                batteryMonitor: UIDeviceBatteryLevelMonitor(),
                connectivityType: NWPathConnectivityTypeProvider()
            ),
            reachability: NWPathReachabilityMonitor(configuration: configuration)
        )
        container.register(PlaybackAnalyticsRecorder.self) { playbackAnalyticsRecorder }

        // Per-environment overrides (e.g. a no-op analytics tracker in
        // Development) branch on `configuration.environment` here as those
        // services are built.

        DependencyContainer.current = container
        return container
    }
}
