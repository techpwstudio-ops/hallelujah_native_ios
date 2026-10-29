import CarPlay
import Observation
import UIKit

/// T49–T52 — builds and drives every CarPlay template. Ports the template
/// half of the Flutter host's `CarPlaySceneDelegate` (tab bar, Home rails,
/// Recents, Search/genres, Library, pushed drill-downs, Now Playing like
/// button) onto native services: repositories for content, `QueueController`
/// for playback, `AudioEngine` for state. There is no bridge and no second
/// player — the phone UI and CarPlay read and drive the same objects, which
/// is what makes "start on the phone, continue in the car" free (T52).
///
/// Now Playing goes beyond the Dart delegate's lone heart: Shuffle, Repeat and
/// (premium) Sleep Timer buttons beside it, and the Up Next button opening the
/// playback queue — each mirrors a control the phone player already has.
///
/// Lifetime: created in `didConnect`, `stop()`ped in `didDisconnect`. Remote
/// commands (play/pause/next/seek) are NOT registered here — the app-wide
/// `NowPlayingCoordinator` already owns `MPRemoteCommandCenter`, and CarPlay's
/// Now Playing screen reads that same command center.
@MainActor
final class CarPlayController {
    /// CarPlay's navigation stack limit. Pushing past it crashes the app with
    /// `clientExceededHierarchyDepthLimit` (the Dart delegate's most common
    /// production crash), so `push` refuses instead.
    private static let maxTemplateDepth = 5

    private let interfaceController: CPInterfaceController
    private let provider: CarPlayContentProvider
    private let engine: AudioEngine
    private let queueController: QueueController
    private let sleepTimer: SleepTimerController
    private let premiumGate: PremiumGate
    private let favourites: any FavouriteRepository
    private let session: Session
    private let artwork: ArtworkSource
    private let logger = AppLogger(category: .carPlay)

    private let homeTemplate: CPListTemplate
    private let recentsTemplate: CPListTemplate
    private let searchTemplate: CPListTemplate
    private let libraryTemplate: CPListTemplate

    private var isActive = false
    /// Set when a push starts, cleared when CarPlay reports it landed — a
    /// second tap while the first template is still animating in is dropped.
    private var isPushing = false

    private var likedList: LiveList?
    private var downloadsList: LiveList?
    /// Open user-playlist drill-downs, by playlist id, so a playlist edit made
    /// elsewhere can re-fetch the one on screen.
    private var playlistSongLists: [String: LiveList] = [:]
    private var changeObserver: NSObjectProtocol?

    private var nowPlayingButtons: [CPNowPlayingImageButton] = []
    /// The row as last submitted to CarPlay, so an unchanged row isn't sent again.
    private var appliedButtons: (row: [CarPlayNowPlayingButton], likeScale: CGFloat)?
    /// 1 normally, enlarged for the instant after a like tap (the "pop").
    private var likeScale: CGFloat = 1.0
    /// Whether the listener's plan includes the sleep timer, which decides if
    /// its button is on Now Playing at all. Re-checked as songs change: the
    /// membership can still be loading when the car connects.
    private var offersSleepTimer = false
    private var nowPlayingObserver: NowPlayingObserver?
    private var lastFavouriteState: (songID: String, isFavorited: Bool)?

    /// The pushed Queue screen, re-rendered in place while it is on top.
    private var queueTemplate: CPListTemplate?
    /// Bumped per render so a slow artwork fetch can't overwrite a newer one.
    private var queueRefreshGeneration = 0

    init(interfaceController: CPInterfaceController, container: DependencyContainer = .current) {
        self.interfaceController = interfaceController
        provider = CarPlayContentProvider(container: container)
        engine = container.resolve()
        queueController = container.resolve()
        sleepTimer = container.resolve()
        premiumGate = container.resolve()
        favourites = container.resolve()
        session = container.resolve()
        artwork = ArtworkSource(session: container.resolve(), proxyHost: AppConfiguration.current.proxyBaseURL.host)

        homeTemplate = Self.makeTab(titleKey: "Home", symbol: "house")
        recentsTemplate = Self.makeTab(titleKey: "Recents", symbol: "clock")
        searchTemplate = Self.makeTab(titleKey: "Search", symbol: "magnifyingglass")
        libraryTemplate = Self.makeTab(titleKey: "Library", symbol: "books.vertical")
    }

    // MARK: - Lifecycle

    /// T49: the tab bar goes up immediately with a loading row per tab; each
    /// tab then fills itself in independently, so nothing blocks on the
    /// slowest request.
    func start() {
        isActive = true
        let tabBar = CPTabBarTemplate(templates: [homeTemplate, recentsTemplate, searchTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        observePlayback()
        observeIntegrationChanges()
        configureNowPlaying()

        Task { await loadAllTabs() }
    }

    func stop() {
        isActive = false
        likedList = nil
        downloadsList = nil
        playlistSongLists = [:]
        queueTemplate = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        if let nowPlayingObserver { CPNowPlayingTemplate.shared.remove(nowPlayingObserver) }
        nowPlayingObserver = nil
    }

    // MARK: - Integration change notifications

    /// `CarIntegrationNotifier` (`car_integration_notifier.dart`): the Recents
    /// tab is fetched once at connect and the Library drill-downs on tap, so
    /// both go stale the moment something changes elsewhere. A list is
    /// re-fetched in place only while it is still the template on top of the
    /// stack, exactly like the Dart/Swift `refresh*` handlers.
    private func observeIntegrationChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: CarIntegrationNotifier.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let change = CarIntegrationNotifier.change(from: notification)
            let playlistID = CarIntegrationNotifier.playlistID(from: notification)
            MainActor.assumeIsolated { self?.handleIntegrationChange(change, playlistID: playlistID) }
        }
    }

    private func handleIntegrationChange(_ change: CarIntegrationNotifier.Change?, playlistID: String?) {
        guard isActive, let change else { return }
        switch change {
        case .recentPlayed:
            Task { await loadRecentsTab() }
        case .favourites:
            refreshIfOnTop(likedList)
        case .downloads:
            refreshIfOnTop(downloadsList)
        case .playlists:
            Task { await loadLibraryTab() }
        case .playlistSongs:
            if let playlistID { refreshIfOnTop(playlistSongLists[playlistID]) }
        }
    }

    private func refreshIfOnTop(_ list: LiveList?) {
        guard let list, interfaceController.topTemplate === list.template else { return }
        Task { await refresh(list) }
    }

    private static func makeTab(titleKey: String.LocalizationValue, symbol: String) -> CPListTemplate {
        let title = String(localized: titleKey)
        let template = CPListTemplate(title: title, sections: [Self.messageSection("Loading…")])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: symbol) ?? UIImage()
        return template
    }

    // MARK: - Tabs

    private func loadAllTabs() async {
        guard await isSignedIn() else {
            let section = Self.messageSection("Sign in on your iPhone to use Hallelujah in the car")
            for template in [homeTemplate, recentsTemplate, searchTemplate, libraryTemplate] {
                template.updateSections([section])
            }
            return
        }
        async let home: Void = loadHomeTab()
        async let recents: Void = loadRecentsTab()
        async let search: Void = loadSearchTab()
        async let library: Void = loadLibraryTab()
        _ = await (home, recents, search, library)
    }

    private func isSignedIn() async -> Bool {
        await session.currentAccessToken() != nil
    }

    /// Rails appear in layout order as each one's artwork finishes, instead
    /// of the whole tab waiting on the slowest rail.
    private func loadHomeTab() async {
        let rails = await provider.homeRails()
        guard isActive else { return }
        guard !rails.isEmpty else {
            homeTemplate.updateSections([Self.messageSection("Nothing to show")])
            return
        }

        var built = [CPListSection?](repeating: nil, count: rails.count)
        await withTaskGroup(of: (Int, [UIImage]).self) { group in
            for (index, rail) in rails.enumerated() {
                let visible = self.visibleRows(of: rail)
                group.addTask { [artwork] in
                    (index, await artwork.images(for: visible))
                }
            }
            for await (index, images) in group {
                guard isActive else { return }
                built[index] = CPListSection(items: [makeRailItem(rails[index], images: images)])
                homeTemplate.updateSections(built.compactMap { $0 })
            }
        }
    }

    private func loadRecentsTab() async {
        let group = await provider.recentRows()
        guard isActive else { return }
        let items = await makeListItems(group, emptyKey: "No recent plays")
        recentsTemplate.updateSections([CPListSection(items: items)])
    }

    /// `CPSearchTemplate` isn't available to audio-entitled apps, so the tab
    /// is an informational row ("ask Siri") plus Browse Genres.
    private func loadSearchTab() async {
        let hint = CPListItem(
            text: String(localized: "Ask Siri to play audio"),
            detailText: String(localized: "Say “Hey Siri, play [song] in Hallelujah”")
        )
        let rows = await provider.genreRows()
        guard isActive else { return }
        let group = CarPlayRowGroup(rows: rows, songs: [], source: Self.noSource)
        let genreItems = await makeListItems(group, emptyKey: nil)
        searchTemplate.updateSections([CPListSection(items: [hint] + genreItems)])
    }

    /// Liked Songs and Downloads show at once; the library's playlists are
    /// added when the merged feed arrives, so the tab doesn't sit on "Loading…".
    private func loadLibraryTab() async {
        let liked = CPListItem(
            text: String(localized: "Liked Songs"),
            detailText: String(localized: "Your favorites")
        )
        liked.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushLikedSongs() }
        }
        let downloads = CPListItem(
            text: String(localized: "Downloads"),
            detailText: String(localized: "Saved for offline")
        )
        downloads.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushDownloads() }
        }
        libraryTemplate.updateSections([CPListSection(items: [liked, downloads])])

        let group = CarPlayRowGroup(rows: await provider.libraryPlaylistRows(), songs: [], source: Self.noSource)
        guard isActive else { return }
        let playlistItems = await makeListItems(group, emptyKey: nil)
        libraryTemplate.updateSections([CPListSection(items: [liked, downloads] + playlistItems)])
    }

    // MARK: - Pushed templates (T51)

    private func pushLikedSongs() {
        likedList = pushSongList(
            title: String(localized: "Liked Songs"),
            emptyKey: "No liked songs yet",
            load: { [provider] in await provider.likedSongs() }
        )
    }

    private func pushDownloads() {
        downloadsList = pushSongList(
            title: String(localized: "Downloads"),
            emptyKey: "No downloads yet",
            load: { [provider] in provider.downloadedSongs() }
        )
    }

    private func pushGroup(title: String, load: @escaping () async -> CarPlayRowGroup) {
        _ = pushSongList(title: title, emptyKey: "No songs", load: load)
    }

    @discardableResult
    private func pushSongList(
        title: String,
        emptyKey: String.LocalizationValue,
        load: @escaping () async -> CarPlayRowGroup
    ) -> LiveList? {
        let list = LiveList(title: title, emptyKey: emptyKey, load: load)
        guard push(list.template) else { return nil }
        Task { await refresh(list) }
        return list
    }

    private func pushList(title: String, items: @escaping () async -> [CPListItem]) {
        let template = CPListTemplate(title: title, sections: [Self.messageSection("Loading…")])
        guard push(template) else { return }
        Task {
            let built = await items()
            template.updateSections([CPListSection(items: built)])
        }
    }

    /// "See all" for a Home rail: the rows are already in hand, no fetch.
    private func pushStatic(title: String, group: CarPlayRowGroup) {
        let template = CPListTemplate(title: title, sections: [Self.messageSection("Loading…")])
        guard push(template) else { return }
        Task {
            let items = await makeListItems(group, emptyKey: "Nothing to show")
            template.updateSections([CPListSection(items: items)])
        }
    }

    private func refresh(_ list: LiveList) async {
        let group = await list.load()
        guard isActive else { return }
        let items = await makeListItems(group, emptyKey: list.emptyKey)
        list.template.updateSections([CPListSection(items: items)])
    }

    /// The single choke point for every push — T53's template-depth and
    /// overlapping-push guards live here, once.
    @discardableResult
    private func push(_ template: CPTemplate) -> Bool {
        guard isActive, !isPushing, interfaceController.templates.count < Self.maxTemplateDepth else {
            return false
        }
        isPushing = true
        interfaceController.pushTemplate(template, animated: true) { [weak self] _, _ in
            Task { @MainActor in self?.isPushing = false }
        }
        return true
    }

    // MARK: - Rows → list items

    private func makeListItems(_ group: CarPlayRowGroup, emptyKey: String.LocalizationValue?) async -> [CPListItem] {
        let rows = Array(group.rows.prefix(CarPlayContentProvider.maxFetchedRows))
        if rows.isEmpty {
            return emptyKey.map { [CPListItem(text: String(localized: $0), detailText: nil)] } ?? []
        }
        let images = await artwork.images(for: rows)
        return zip(rows, images).map { row, image in makeListItem(row, image: image, group: group) }
    }

    private func makeListItem(_ row: CarPlayRow, image: UIImage, group: CarPlayRowGroup) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.subtitle, image: image)
        if case .song(let index) = row.kind {
            item.isPlaying = group.songs.indices.contains(index) && group.songs[index].id == engine.currentSong?.id
            item.playingIndicatorLocation = .trailing
        } else {
            item.accessoryType = .disclosureIndicator
        }
        item.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.activate(row, in: group) }
        }
        return item
    }

    private func activate(_ row: CarPlayRow, in group: CarPlayRowGroup) {
        switch row.kind {
        case .song(let index):
            play(group.songs, startIndex: index, source: group.source)
        case .recentSong(let songID):
            Task {
                guard let song = await provider.resolveSong(id: songID) else {
                    logger.warning("CarPlay recent song \(songID) could not be resolved")
                    return
                }
                play([song], startIndex: 0, source: QueueAttribution(playerType: .home, id: "recent-all", title: ""))
            }
        case .creator(let id):
            pushGroup(title: row.title) { [provider] in await provider.creatorSongs(id: id, title: row.title) }
        case .companyPlaylist(let id):
            pushGroup(title: row.title) { [provider] in await provider.companyPlaylistSongs(id: id, title: row.title) }
        case .creatorPlaylist(let id):
            pushGroup(title: row.title) { [provider] in await provider.creatorPlaylistSongs(id: id, title: row.title) }
        case .userPlaylist(let id):
            playlistSongLists[id] = pushSongList(
                title: row.title,
                emptyKey: "No songs",
                load: { [provider] in await provider.userPlaylistSongs(id: id, title: row.title) }
            )
        case .genre(let id):
            pushGroup(title: row.title) { [provider] in await provider.genreSongs(id: id, title: row.title) }
        }
    }

    /// Every song a CarPlay row or rail tile starts goes through here, so a tap
    /// anywhere opens Now Playing. It goes up at tap time rather than once
    /// playback has begun: `engine.play` waits on the stream to resolve, and
    /// the car would otherwise sit on the list for that long. The cost is that
    /// Now Playing shows the previous track (or nothing) until the engine
    /// publishes the new song to `MPNowPlayingInfoCenter`.
    private func play(_ songs: [Song], startIndex: Int, source: QueueAttribution) {
        guard songs.indices.contains(startIndex) else { return }
        showNowPlaying()
        Task { await queueController.play(songs: songs, startIndex: startIndex, source: source) }
    }

    // MARK: - Home rails (T50)

    private func visibleRows(of rail: CarPlayRail) -> [CarPlayRow] {
        let limit = rail.isTrendingGrid ? Self.trendingGridLimit : Int(CPMaximumNumberOfGridImages)
        return Array(rail.group.rows.prefix(limit))
    }

    /// Trending renders as a 2-column grid; 6 items fills it.
    private static let trendingGridLimit = 6

    /// A Home rail is one `CPListImageRowItem`: a horizontally scrolling
    /// strip of artwork, degrading by the head unit's iOS version — iOS 26+
    /// card/condensed elements (image + title + subtitle), 17.4+ image titles,
    /// older images only. Tapping a tile plays/drills as the row's kind says;
    /// tapping the row itself opens "See All".
    private func makeRailItem(_ rail: CarPlayRail, images: [UIImage]) -> CPListImageRowItem {
        let rows = visibleRows(of: rail)
        let item: CPListImageRowItem

        if #available(iOS 26.0, *), rail.isTrendingGrid {
            let elements = rows.enumerated().map { index, row in
                CPListImageRowItemCondensedElement(
                    image: images[index],
                    imageShape: row.isCircularArtwork ? .circular : .roundedRectangle,
                    title: row.title,
                    subtitle: row.subtitle,
                    accessorySymbolName: nil
                )
            }
            item = CPListImageRowItem(text: rail.title, condensedElements: elements, allowsMultipleLines: true)
        } else if #available(iOS 26.0, *) {
            let elements = rows.enumerated().map { index, row in
                CPListImageRowItemCardElement(
                    image: images[index],
                    showsImageFullHeight: false,
                    title: row.title,
                    subtitle: row.subtitle,
                    // `nil` = the system's own card surface. A `.clear` tint
                    // removed that surface, so the title/subtitle landed
                    // straight on the head unit's backdrop in a colour chosen
                    // for the card, and went unreadable on some cars.
                    tintColor: nil
                )
            }
            item = CPListImageRowItem(text: rail.title, cardElements: elements, allowsMultipleLines: false)
        } else if #available(iOS 17.4, *) {
            item = CPListImageRowItem(text: rail.title, images: images, imageTitles: rows.map(\.title))
        } else {
            item = CPListImageRowItem(text: rail.title, images: images)
        }

        item.listImageRowHandler = { [weak self] _, index, completion in
            completion()
            MainActor.assumeIsolated {
                guard let self, rows.indices.contains(index) else { return }
                self.activate(rows[index], in: rail.group)
            }
        }
        item.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushStatic(title: rail.title, group: rail.group) }
        }
        return item
    }

    // MARK: - Engine observation and Now Playing (T52)

    /// Brings CarPlay's Now Playing screen to the top once the user starts a
    /// song (`CPNowPlayingTemplate.sharedTemplate` is documented as the thing
    /// to present "in response to the user selecting a playable item"). CarPlay
    /// also presents it on its own in some cases, so it may already be on
    /// screen or lower in the stack: it is pushed only when absent, and popped
    /// back to when something sits above it.
    func showNowPlaying() {
        guard isActive else { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        if interfaceController.topTemplate === nowPlaying { return }
        if interfaceController.templates.contains(where: { $0 === nowPlaying }) {
            interfaceController.pop(to: nowPlaying, animated: true, completion: nil)
        } else {
            push(nowPlaying)
        }
    }

    /// Re-arms itself after every change, the same pattern as
    /// `NowPlayingCoordinator.trackEngine`. Reads only what it reacts to:
    /// the current song's identity and favourite flag, the queue, the shuffle
    /// and repeat modes, and whether a sleep timer is running — everything the
    /// Now Playing buttons, the Queue screen and the "now playing" row dots
    /// show, plus the Liked Songs refresh.
    private func observePlayback() {
        guard isActive else { return }
        withObservationTracking {
            _ = engine.currentSong?.id
            _ = engine.currentSong?.isFavorited
            _ = queueController.queue
            _ = queueController.isShuffled
            _ = queueController.repeatMode
            _ = sleepTimer.isActive
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.playbackChanged()
                self?.observePlayback()
            }
        }
    }

    private func playbackChanged() {
        guard isActive else { return }
        refreshNowPlayingButtons()
        refreshQueueIfOnTop()
        Task { await refreshSleepTimerAvailability() }

        let current = engine.currentSong
        let newState = current.map { (songID: $0.id, isFavorited: $0.isFavorited) }
        // Same song, different favourite flag -> Liked Songs is stale.
        if let last = lastFavouriteState, let newState, last.songID == newState.songID,
           last.isFavorited != newState.isFavorited, let likedList {
            Task { await refresh(likedList) }
        }
        lastFavouriteState = newState
    }

    /// What only CarPlay's shared Now Playing screen has: the button row, and
    /// the Up Next button, retitled "Queue" and opening our playback queue
    /// (Spotify's is "Queue and Jam"; there is no Jam here, so just the queue).
    private func configureNowPlaying() {
        let template = CPNowPlayingTemplate.shared
        template.isUpNextButtonEnabled = true
        template.upNextTitle = String(localized: "Queue")
        let observer = NowPlayingObserver { [weak self] in self?.pushQueue() }
        template.add(observer)
        nowPlayingObserver = observer

        refreshNowPlayingButtons()
        Task { await refreshSleepTimerAvailability() }
    }

    /// `CPNowPlayingImageButton.image` is get-only — changing what a button
    /// shows means building a new one and resubmitting the row, so that only
    /// happens when the row differs from what CarPlay already has.
    private func refreshNowPlayingButtons() {
        guard isActive else { return }
        let row = CarPlayNowPlayingButton.row(
            isFavorited: engine.currentSong?.isFavorited ?? false,
            isShuffled: queueController.isShuffled,
            repeatMode: queueController.repeatMode,
            offersSleepTimer: offersSleepTimer,
            isSleepTimerRunning: sleepTimer.isActive
        )
        guard appliedButtons?.row != row || appliedButtons?.likeScale != likeScale else { return }
        appliedButtons = (row, likeScale)
        nowPlayingButtons = row.map(makeNowPlayingButton)
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(nowPlayingButtons)
    }

    /// Custom image buttons throughout, not CarPlay's own shuffle and repeat
    /// buttons: those take their selected state from what the app reports
    /// through `MPRemoteCommandCenter`, which `NowPlayingCoordinator` owns and
    /// registers no shuffle or repeat commands on. An image button's selected
    /// state is ours to set, and its tap goes straight to the handler.
    private func makeNowPlayingButton(_ slot: CarPlayNowPlayingButton) -> CPNowPlayingImageButton {
        let scale = slot.kind == .like ? likeScale : 1.0
        let button = CPNowPlayingImageButton(image: Self.glyphImage(slot.symbol, scale: scale)) { [weak self] _ in
            MainActor.assumeIsolated { self?.nowPlayingButtonTapped(slot.kind) }
        }
        button.isSelected = slot.isSelected
        return button
    }

    private func nowPlayingButtonTapped(_ kind: CarPlayNowPlayingButton.Kind) {
        switch kind {
        case .like: toggleFavouriteFromCarPlay()
        case .shuffle: Task { await queueController.toggleShuffle() }
        case .repeatMode: queueController.cycleRepeatMode()
        case .sleepTimer: pushSleepTimer()
        }
    }

    private func refreshSleepTimerAvailability() async {
        let allowed = await premiumGate.allows(.sleepTimer)
        guard isActive, allowed != offersSleepTimer else { return }
        offersSleepTimer = allowed
        refreshNowPlayingButtons()
    }

    /// Optimistic flip + a brief enlarged frame ("pop"), reverted if the
    /// request fails — same flow as the phone's `FavouriteToggleButton`.
    private func toggleFavouriteFromCarPlay() {
        guard let song = engine.currentSong else { return }
        let target = !song.isFavorited
        engine.setCurrentSongFavorited(target, songId: song.id)
        likeScale = Self.likePopScale
        refreshNowPlayingButtons()

        Task {
            try? await Task.sleep(for: Self.likePopDuration)
            likeScale = 1.0
            refreshNowPlayingButtons()
        }
        Task {
            do {
                try await favourites.toggleSongFavorite(songId: song.id, isFavorited: target)
            } catch {
                logger.warning("CarPlay favourite toggle failed: \(error)")
                engine.setCurrentSongFavorited(!target, songId: song.id)
            }
        }
    }

    private static let likePopScale: CGFloat = 1.3
    private static let likePopDuration: Duration = .milliseconds(180)

    /// Rendered onto a fixed canvas so the pop's scale steps share one
    /// footprint and CarPlay doesn't reflow the button. Left uncoloured on
    /// purpose: CarPlay recolours custom button images to its own theme.
    private static func glyphImage(_ symbol: String, scale: CGFloat) -> UIImage {
        let canvas = CGSize(width: 40, height: 40)
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let glyph = UIImage(systemName: symbol, withConfiguration: configuration) ?? UIImage()
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let size = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
            glyph.draw(in: CGRect(origin: origin, size: size))
        }
    }

    // MARK: - Queue

    /// The Up Next button's screen: the playing song, then what follows it.
    /// Rows jump within the existing queue — they must not go through
    /// `makeListItem`, whose song rows rebuild the queue from a fresh list.
    private func pushQueue() {
        let template = CPListTemplate(title: String(localized: "Queue"), sections: [Self.messageSection("Loading…")])
        guard push(template) else { return }
        queueTemplate = template
        refreshQueue()
    }

    /// A song change moves the "playing" row; a shuffle, or an edit made on the
    /// phone, reorders the rest — so the screen follows while it is showing.
    private func refreshQueueIfOnTop() {
        guard let queueTemplate, interfaceController.topTemplate === queueTemplate else { return }
        refreshQueue()
    }

    private func refreshQueue() {
        queueRefreshGeneration += 1
        let generation = queueRefreshGeneration
        Task {
            let sections = await makeQueueSections()
            guard isActive, generation == queueRefreshGeneration else { return }
            queueTemplate?.updateSections(sections)
        }
    }

    private func makeQueueSections() async -> [CPListSection] {
        guard let queue = queueController.queue,
              let window = CarPlayQueueWindow(queue: queue, limit: CarPlayContentProvider.maxFetchedRows)
        else {
            return [Self.messageSection("Queue is empty")]
        }
        let rows = provider.songGroup(window.songs, source: queue.source).rows
        let images = await artwork.images(for: rows)
        let items = rows.indices.map { offset in
            makeQueueItem(
                rows[offset],
                image: images[offset],
                song: window.songs[offset],
                queueIndex: window.startIndex + offset,
                isCurrent: offset == 0
            )
        }

        let nowPlaying = String(localized: "Now Playing")
        var sections = [CPListSection(items: [items[0]], header: nowPlaying, sectionIndexTitle: nil)]
        if items.count > 1 {
            let upNext = String(localized: "Up Next")
            sections.append(CPListSection(items: Array(items.dropFirst()), header: upNext, sectionIndexTitle: nil))
        }
        return sections
    }

    private func makeQueueItem(
        _ row: CarPlayRow,
        image: UIImage,
        song: Song,
        queueIndex: Int,
        isCurrent: Bool
    ) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.subtitle, image: image)
        item.isPlaying = isCurrent
        item.playingIndicatorLocation = .trailing
        item.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.selectQueueSong(id: song.id, at: queueIndex) }
        }
        return item
    }

    /// Back to Now Playing at once, then the jump — the same order as `play`.
    /// The playing row only returns to Now Playing: restarting the track you are
    /// already hearing is not what a tap on it means in a car.
    private func selectQueueSong(id: String, at index: Int) {
        showNowPlaying()
        guard let queue = queueController.queue else { return }
        // The row was built from an earlier queue; a shuffle or reorder since
        // then can have moved the song, so find it again by identity.
        let target = queue.songs.indices.contains(index) && queue.songs[index].id == id
            ? index
            : queue.songs.firstIndex(where: { $0.id == id })
        guard let target, target != queue.currentIndex else { return }
        Task { await queueController.jump(to: target) }
    }

    // MARK: - Sleep timer

    /// The Sleep Timer button's screen: the phone sheet's six durations, plus
    /// Turn Off while one is running. Picking returns to Now Playing, where the
    /// button lights (or goes dark) — CarPlay has no toast to confirm it.
    private func pushSleepTimer() {
        push(CPListTemplate(title: String(localized: "Sleep Timer"), sections: sleepTimerSections()))
    }

    private func sleepTimerSections() -> [CPListSection] {
        let options = SleepTimerController.options.map { minutes -> CPListItem in
            let isSelected = sleepTimer.selectedMinutes == minutes
            let item = CPListItem(
                text: String(localized: "\(minutes) minutes"),
                detailText: isSelected ? String(localized: "Active · \(minutes)m selected") : nil
            )
            item.handler = { [weak self] _, completion in
                completion()
                MainActor.assumeIsolated {
                    self?.sleepTimer.start(minutes: minutes)
                    self?.showNowPlaying()
                }
            }
            return item
        }
        var sections = [CPListSection(items: options)]
        if sleepTimer.isActive {
            let turnOff = CPListItem(text: String(localized: "Turn Off Timer"), detailText: nil)
            turnOff.handler = { [weak self] _, completion in
                completion()
                MainActor.assumeIsolated {
                    self?.sleepTimer.cancel()
                    self?.showNowPlaying()
                }
            }
            sections.append(CPListSection(items: [turnOff]))
        }
        return sections
    }

    // MARK: - Small helpers

    private static let noSource = QueueAttribution(playerType: .home, id: nil, title: "")

    private static func messageSection(_ key: String.LocalizationValue) -> CPListSection {
        CPListSection(items: [CPListItem(text: String(localized: key), detailText: nil)])
    }
}

// MARK: - Supporting types

/// A pushed list that can re-fetch itself in place (Liked Songs, Downloads).
@MainActor
private final class LiveList {
    let template: CPListTemplate
    let emptyKey: String.LocalizationValue
    let load: () async -> CarPlayRowGroup

    init(title: String, emptyKey: String.LocalizationValue, load: @escaping () async -> CarPlayRowGroup) {
        template = CPListTemplate(title: title, sections: [CarPlayController.loadingSection()])
        self.emptyKey = emptyKey
        self.load = load
    }
}

extension CarPlayController {
    fileprivate static func loadingSection() -> CPListSection {
        messageSection("Loading…")
    }
}

/// `CPNowPlayingTemplate` reports its Up Next button through an observer
/// protocol, which needs an `NSObject`; the controller isn't one.
private final class NowPlayingObserver: NSObject, CPNowPlayingTemplateObserver {
    private let upNextTapped: @MainActor () -> Void

    init(upNextTapped: @escaping @MainActor () -> Void) {
        self.upNextTapped = upNextTapped
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        // Copied out so the main-actor closure doesn't capture this non-Sendable object.
        let handler = upNextTapped
        MainActor.assumeIsolated { handler() }
    }
}

/// Off-main artwork fetching for a batch of rows, concurrent and
/// order-preserving. Missing artwork falls back to a music-note placeholder
/// so every row keeps its image slot.
private struct ArtworkSource: Sendable {
    let session: Session
    let proxyHost: String?

    func images(for rows: [CarPlayRow]) async -> [UIImage] {
        let placeholder = UIImage(systemName: "music.note") ?? UIImage()
        var images = [UIImage](repeating: placeholder, count: rows.count)
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, row) in rows.enumerated() {
                group.addTask { (index, await image(for: row)) }
            }
            for await (index, image) in group {
                if let image { images[index] = image }
            }
        }
        return images
    }

    private func image(for row: CarPlayRow) async -> UIImage? {
        guard let url = row.artworkURL else { return nil }
        var headers: [String: String]?
        if let proxyHost, url.host == proxyHost {
            headers = ["Authorization": "Bearer \(await session.currentAccessToken() ?? "")"]
        }
        guard let raw = await CarPlayArtworkLoader.shared.image(for: url, headers: headers) else { return nil }
        return row.isCircularArtwork ? CarPlayArtworkLoader.circular(raw) : raw
    }
}
