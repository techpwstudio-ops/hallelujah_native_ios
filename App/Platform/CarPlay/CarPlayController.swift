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

    private var likeButton: CPNowPlayingImageButton?
    private var lastFavouriteState: (songID: String, isFavorited: Bool)?

    init(interfaceController: CPInterfaceController, container: DependencyContainer = .current) {
        self.interfaceController = interfaceController
        provider = CarPlayContentProvider(container: container)
        engine = container.resolve()
        queueController = container.resolve()
        favourites = container.resolve()
        session = container.resolve()
        artwork = ArtworkSource(session: container.resolve(), proxyHost: AppConfiguration.current.proxyBaseURL.host)

        homeTemplate = Self.makeTab(titleKey: "carplay.tab.home", symbol: "house")
        recentsTemplate = Self.makeTab(titleKey: "carplay.tab.recents", symbol: "clock")
        searchTemplate = Self.makeTab(titleKey: "carplay.tab.search", symbol: "magnifyingglass")
        libraryTemplate = Self.makeTab(titleKey: "carplay.tab.library", symbol: "books.vertical")
    }

    // MARK: - Lifecycle

    /// T49: the tab bar goes up immediately with a loading row per tab; each
    /// tab then fills itself in independently, so nothing blocks on the
    /// slowest request.
    func start() {
        isActive = true
        let tabBar = CPTabBarTemplate(templates: [homeTemplate, recentsTemplate, searchTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        observeEngine()
        refreshLikeButton()

        Task { await loadAllTabs() }
    }

    func stop() {
        isActive = false
        likedList = nil
        downloadsList = nil
    }

    private static func makeTab(titleKey: String.LocalizationValue, symbol: String) -> CPListTemplate {
        let title = String(localized: titleKey)
        let template = CPListTemplate(title: title, sections: [Self.messageSection("carplay.loading")])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: symbol) ?? UIImage()
        return template
    }

    // MARK: - Tabs

    private func loadAllTabs() async {
        guard await isSignedIn() else {
            let section = Self.messageSection("carplay.signInRequired")
            for template in [homeTemplate, recentsTemplate, searchTemplate, libraryTemplate] {
                template.updateSections([section])
            }
            return
        }
        async let home: Void = loadHomeTab()
        async let recents: Void = loadRecentsTab()
        async let search: Void = loadSearchTab()
        loadLibraryTab()
        _ = await (home, recents, search)
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
            homeTemplate.updateSections([Self.messageSection("carplay.nothingToShow")])
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
        let items = await makeListItems(group, emptyKey: "carplay.recents.empty")
        recentsTemplate.updateSections([CPListSection(items: items)])
    }

    /// `CPSearchTemplate` isn't available to audio-entitled apps, so the tab
    /// is an informational row ("ask Siri") plus Browse Genres.
    private func loadSearchTab() async {
        let hint = CPListItem(
            text: String(localized: "carplay.search.hint.title"),
            detailText: String(localized: "carplay.search.hint.detail")
        )
        let rows = await provider.genreRows()
        guard isActive else { return }
        let group = CarPlayRowGroup(rows: rows, songs: [], source: Self.noSource)
        let genreItems = await makeListItems(group, emptyKey: nil)
        searchTemplate.updateSections([CPListSection(items: [hint] + genreItems)])
    }

    private func loadLibraryTab() {
        let liked = CPListItem(
            text: String(localized: "carplay.library.liked.title"),
            detailText: String(localized: "carplay.library.liked.detail")
        )
        liked.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushLikedSongs() }
        }
        let downloads = CPListItem(
            text: String(localized: "carplay.library.downloads.title"),
            detailText: String(localized: "carplay.library.downloads.detail")
        )
        downloads.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushDownloads() }
        }
        let playlists = CPListItem(
            text: String(localized: "carplay.library.playlists.title"),
            detailText: String(localized: "carplay.library.playlists.detail")
        )
        playlists.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushAllPlaylists() }
        }
        libraryTemplate.updateSections([CPListSection(items: [liked, downloads, playlists])])
    }

    // MARK: - Pushed templates (T51)

    private func pushLikedSongs() {
        likedList = pushSongList(
            title: String(localized: "carplay.library.liked.title"),
            emptyKey: "carplay.liked.empty",
            load: { [provider] in await provider.likedSongs() }
        )
    }

    private func pushDownloads() {
        downloadsList = pushSongList(
            title: String(localized: "carplay.library.downloads.title"),
            emptyKey: "carplay.downloads.empty",
            load: { [provider] in provider.downloadedSongs() }
        )
    }

    private func pushAllPlaylists() {
        pushList(title: String(localized: "carplay.library.playlists.title")) { [weak self] in
            guard let self else { return [] }
            let rows = await provider.allPlaylistRows()
            let group = CarPlayRowGroup(rows: rows, songs: [], source: Self.noSource)
            return await makeListItems(group, emptyKey: "carplay.playlists.empty")
        }
    }

    private func pushGroup(title: String, load: @escaping () async -> CarPlayRowGroup) {
        _ = pushSongList(title: title, emptyKey: "carplay.noSongs", load: load)
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
        let template = CPListTemplate(title: title, sections: [Self.messageSection("carplay.loading")])
        guard push(template) else { return }
        Task {
            let built = await items()
            template.updateSections([CPListSection(items: built)])
        }
    }

    /// "See all" for a Home rail: the rows are already in hand, no fetch.
    private func pushStatic(title: String, group: CarPlayRowGroup) {
        let template = CPListTemplate(title: title, sections: [Self.messageSection("carplay.loading")])
        guard push(template) else { return }
        Task {
            let items = await makeListItems(group, emptyKey: "carplay.nothingToShow")
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
                guard let song = await provider.resolveSong(id: songID, title: row.title) else {
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
            pushGroup(title: row.title) { [provider] in await provider.userPlaylistSongs(id: id, title: row.title) }
        case .genre(let id):
            pushGroup(title: row.title) { [provider] in await provider.genreSongs(id: id, title: row.title) }
        }
    }

    private func play(_ songs: [Song], startIndex: Int, source: QueueAttribution) {
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
                    tintColor: .clear
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
                activate(rows[index], in: rail.group)
            }
        }
        item.handler = { [weak self] _, completion in
            completion()
            MainActor.assumeIsolated { self?.pushStatic(title: rail.title, group: rail.group) }
        }
        return item
    }

    // MARK: - Engine observation and Now Playing (T52)

    /// Re-arms itself after every change, the same pattern as
    /// `NowPlayingCoordinator.trackEngine`. Reads only what it reacts to:
    /// the current song's identity and favourite flag (like button, "now
    /// playing" row dots, Liked Songs refresh) and the download catalogue.
    private func observeEngine() {
        guard isActive else { return }
        withObservationTracking {
            _ = engine.currentSong?.id
            _ = engine.currentSong?.isFavorited
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.engineChanged()
                self?.observeEngine()
            }
        }
    }

    private func engineChanged() {
        guard isActive else { return }
        refreshLikeButton()

        let current = engine.currentSong
        let newState = current.map { (songID: $0.id, isFavorited: $0.isFavorited) }
        // Same song, different favourite flag -> Liked Songs is stale.
        if let last = lastFavouriteState, let newState, last.songID == newState.songID,
           last.isFavorited != newState.isFavorited, let likedList {
            Task { await refresh(likedList) }
        }
        lastFavouriteState = newState
    }

    /// `CPNowPlayingImageButton.image` is get-only — changing what the button
    /// shows means building a new button and resubmitting it.
    private func refreshLikeButton(scale: CGFloat = 1.0) {
        let isFavorited = engine.currentSong?.isFavorited ?? false
        let button = CPNowPlayingImageButton(image: Self.heartImage(filled: isFavorited, scale: scale)) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleFavouriteFromCarPlay() }
        }
        button.isSelected = isFavorited
        likeButton = button
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([button])
    }

    /// Optimistic flip + a brief enlarged frame ("pop"), reverted if the
    /// request fails — same flow as the phone's `FavouriteToggleButton`.
    private func toggleFavouriteFromCarPlay() {
        guard let song = engine.currentSong else { return }
        let target = !song.isFavorited
        engine.setCurrentSongFavorited(target, songId: song.id)
        refreshLikeButton(scale: Self.likePopScale)

        Task {
            try? await Task.sleep(for: Self.likePopDuration)
            if engine.currentSong?.id == song.id { refreshLikeButton() }
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
    private static func heartImage(filled: Bool, scale: CGFloat) -> UIImage {
        let canvas = CGSize(width: 40, height: 40)
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let symbol = UIImage(systemName: filled ? "heart.fill" : "heart", withConfiguration: configuration) ?? UIImage()
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
            symbol.draw(in: CGRect(origin: origin, size: size))
        }
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
        messageSection("carplay.loading")
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
