import Observation
import SwiftUI

/// Ports `AudioPlayerScreen` (`lib/views/home/audio_player_screen.dart`) with
/// D12 parity: black `Scaffold`, an app bar with a back arrow, the
/// "playing from" title and a vertical-dots menu, then a scrolling body —
/// full-width artwork pager, 20pt-padded column (headline row with favourite
/// and add-to-playlist, 6pt scrubber, transport row, sleep-timer badge, a
/// queue / share row, lyrics card and description). Whatever Flutter keeps in
/// the song menu (download, sleep timer, tip) is reached through the menu
/// here too; the standalone download / sleep / output-picker / tip buttons the
/// first native pass invented are gone. `body` still branches to
/// `AdBreakView` while an ad break is active, as `AudioPlayerScreen` swaps in
/// `AdBreakScreen`.
///
/// The ad takeover (`PlayerAdOverlay`) covers the artwork pager and the
/// lingering `AdCompanionBanner` is pinned to the bottom, as in Flutter.
///
/// The creator card, credits and "More like this" rail come from
/// `SongMetaSections`. Not ported: the artwork pager's overscroll-to-skip
/// gesture.
struct FullPlayerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    /// Chapters, speakers and transcript for the song playing (Phase 1/2). Shared
    /// with the transcript screen, so the two never fetch or clock separately.
    @State private var timelineStore: EpisodeTimelineStore = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var playerAd: PlayerAdController = DependencyContainer.current.resolve()
    @State private var sleepTimer: SleepTimerController = DependencyContainer.current.resolve()
    /// Cover or silent video: the listener's choice, shared by the artwork and the icon button that flips it.
    @State private var videoMode: PlayerVideoModeStore = DependencyContainer.current.resolve()
    @State private var videoSource: PlayerVideoSource = DependencyContainer.current.resolve()
    /// Which rendition of the video plays; also changed from Settings and from the menu on the picture.
    @State private var videoQuality: VideoQualityStore = DependencyContainer.current.resolve()
    @State private var premiumGate: PremiumGate = DependencyContainer.current.resolve()
    /// Video is a premium feature: the same `PremiumGate` check as downloads, the sleep timer and
    /// audio quality. Resolved on appear and on every track change; starts unlocked so a premium
    /// listener never sees the badge flash.
    @State private var isVideoLocked = false
    /// The video is open full screen in landscape (`PlayerVideoFullScreenView`).
    @State private var isVideoFullScreen = false
    @State private var isSharePresented = false
    @State private var isQueuePresented = false
    @State private var isAddToPlaylistPresented = false
    @State private var isSleepTimerSheetPresented = false
    @State private var menuSong: Song?
    @State private var tipPurchases: TipPurchaseManager = DependencyContainer.current.resolve()
    @State private var tipRepository: any TipRepository = DependencyContainer.current.resolve()
    /// `offeringsProvider`: fetched when the player opens, so each opening
    /// picks up whatever the admin panel changed. Empty (not loaded, no
    /// offering for this store, or a failed request) hides the tip button.
    @State private var offerings: [Offering] = []
    @State private var isTipSheetPresented = false
    /// The player's own size: picks the stacked or side-by-side layout and
    /// sizes the artwork on a tablet, foldable or Mac window.
    @State private var playerSize: CGSize = .zero

    private var song: Song? { engine.currentSong }

    /// Nothing — the queue, a menu, a sheet, a pushed page — is covering the
    /// player, so the ad's clock may run (`ModalRoute.isCurrentOf`).
    private var isPlayerUncovered: Bool {
        coordinator.playerPath.isEmpty
            && !isSharePresented && !isQueuePresented && !isAddToPlaylistPresented
            && !isSleepTimerSheetPresented && !isTipSheetPresented && menuSong == nil
    }

    /// The silent video is on screen and in front: the app is not in the background and no page is
    /// pushed over the player. Sheets over the player do not count, so the video keeps playing
    /// under one; that is why this is not `isPlayerUncovered`.
    private var isVideoVisible: Bool {
        // Full screen runs its own player; this one lets go so only one is ever open.
        scenePhase != .background && coordinator.playerPath.isEmpty && !isVideoFullScreen
    }

    /// What the artwork pager needs to lay the video over the cover.
    private var videoContext: PlayerVideoContext {
        PlayerVideoContext(
            mode: videoMode,
            source: videoSource,
            quality: videoQuality,
            clock: EngineAudioClock(engine: engine),
            playingSongId: engine.currentSong?.id,
            isVisible: isVideoVisible,
            onUnavailable: {
                videoMode.showCover()
                toastCenter.show(String(localized: "Video isn't available right now"))
            },
            isLocked: isVideoLocked,
            onExpand: { isVideoFullScreen = true }
        )
    }

    /// The playing item's length: the engine's once it is known, else the song's own.
    private var playbackDuration: TimeInterval {
        engine.currentItemDuration ?? TimeInterval(song?.duration ?? 0)
    }

    @ViewBuilder
    private var moreButton: some View {
        if song != nil {
            // `Icons.more_vert`.
            AppToolbarCircleButton(systemName: "ellipsis", label: "More", rotation: .degrees(90)) { menuSong = song }
        }
    }

    private var subtitle: String { song?.artistLine ?? "" }

    var body: some View {
        Group {
            if adPacing.isAdBreak {
                AdBreakView(pacing: adPacing)
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                playerContent
            }
        }
        .background(PlayerStyle.black.ignoresSafeArea())
        .appSheet(isPresented: $isSharePresented, detents: [.large]) {
            if let song {
                ShareSheetView(
                    target: .song(id: song.id),
                    title: song.title ?? "",
                    subtitle: subtitle,
                    artworkURL: ArtworkURLResolver().resolve(
                        path: song.displayImage,
                        variant: .lg,
                        allowedVariants: song.displayImageVariants
                    )
                )
            }
        }
        // `showQueueSheet` -> `showAppSheet(QueuePage)`.
        .appSheet(isPresented: $isQueuePresented, detents: QueueView.sheetDetents) {
            QueueView(isSheet: true)
        }
        .appSheet(isPresented: $isAddToPlaylistPresented) {
            if let song {
                PlayerAddToPlaylistSheet(song: song) { outcome in
                    switch outcome {
                    case .message(let text):
                        toastCenter.show(text)
                        isAddToPlaylistPresented = false
                    case .notice(let text):
                        toastCenter.show(text)
                    case .createPlaylist(let songID):
                        // The player is a full-screen cover above the tab
                        // stacks, so it has to close for the new screen to show.
                        isAddToPlaylistPresented = false
                        coordinator.dismissFullScreen()
                        coordinator.push(.createPlaylist(userPlaylistID: nil, songType: nil, songID: songID))
                    default:
                        isAddToPlaylistPresented = false
                    }
                }
            }
        }
        .appSheet(isPresented: $isTipSheetPresented) {
            if let song {
                TipDonationSheet(
                    artistName: song.creator?.displayName ?? song.creator?.name ?? song.primaryArtists,
                    offerings: offerings
                ) { offering, note in
                    sendTip(offering: offering, note: note, song: song)
                }
            }
        }
        .task {
            guard AppConfiguration.current.featureFlags.tipButtonEnabled else { return }
            offerings = await tipRepository.offerings()
        }
        .task(id: song?.id) {
            await timelineStore.load(for: song)
        }
        // A fresh look at the connection and battery for each episode, which Auto picks its quality from.
        .task(id: song?.id) {
            await videoQuality.refreshConditions()
        }
        .fullScreenCover(isPresented: $isVideoFullScreen) {
            if let song, song.hasVideo {
                PlayerVideoFullScreenView(
                    song: song,
                    engine: engine,
                    source: videoSource,
                    chapters: timelineStore.chapters,
                    duration: playbackDuration,
                    quality: videoQuality,
                    onUnavailable: {
                        isVideoFullScreen = false
                        videoMode.showCover()
                        toastCenter.show(String(localized: "Video isn't available right now"))
                    },
                    onClose: { isVideoFullScreen = false }
                )
            }
        }
        // However full screen closes, turn back upright at once rather than after the cover's
        // dismissal animation.
        .onChange(of: isVideoFullScreen) { _, isFullScreen in
            if !isFullScreen { OrientationLock.portrait() }
        }
        // Back on the cover (or locked): full screen has nothing to show.
        .onChange(of: videoMode.showsVideo) { _, showsVideo in
            if !showsVideo { isVideoFullScreen = false }
        }
        .task(id: song?.id) {
            let locked = await !premiumGate.allows(.videoMode)
            isVideoLocked = locked
            // A listener whose subscription has lapsed is not left on video.
            if locked, videoMode.showsVideo { videoMode.showCover() }
        }
        .songMenu(song: $menuSong, leavesPlayer: true)
        .sleepTimerSheet(isPresented: $isSleepTimerSheetPresented)
        // The timer pauses playback itself (it usually fires with the phone
        // locked); the screen's only job is to leave and say so.
        .onChange(of: sleepTimer.firedCount) {
            coordinator.dismissFullScreen()
            toastCenter.show("Sleep timer ended. Time to rest")
        }
        // `BlocListener(listenWhen: songId != null -> null)` pops the player.
        .onChange(of: engine.currentSong?.id) { _, newValue in
            if newValue == nil { coordinator.dismissFullScreen() }
        }
        // The transcript clock runs only while playing, outside ad breaks, in the
        // active scene, and with the read-along or transcript on screen (Phase 2).
        .onAppear(perform: syncTranscriptClock)
        .onChange(of: engine.status) { _, _ in syncTranscriptClock() }
        .onChange(of: adPacing.isAdBreak) { _, _ in syncTranscriptClock() }
        .onChange(of: scenePhase) { _, _ in syncTranscriptClock() }
        .onChange(of: engine.seekGeneration) { _, _ in timelineStore.clock.seeked() }
    }

    private func syncTranscriptClock() {
        let clock = timelineStore.clock
        clock.setPlaying(engine.status == .playing)
        clock.setAdBreak(adPacing.isAdBreak)
        clock.setSceneActive(scenePhase == .active)
    }

    private var playerContent: some View {
        ZStack {
            if AdaptiveLayout.isSideBySide(playerSize) {
                sideBySideContent
            } else {
                stackedContent
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { playerSize = $0 }
        .background(PlayerStyle.black.ignoresSafeArea())
        // `AdCompanionBanner`, bottom-aligned over the body.
        .overlay(alignment: .bottom) {
            AdCompanionBanner(pacing: adPacing)
        }
        .toolbar {
            AppBackToolbarItem { coordinator.dismissFullScreen() }
            ToolbarItem(placement: .principal) {
                PlayingFromTitle(queueController: queueController, song: song)
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { moreButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { moreButton }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(PlayerStyle.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// The phone layout: artwork edge to edge, then the controls and the
    /// song's details in one scrolling column. On a wider window (tablet in
    /// portrait, narrow Mac window, unfolded foldable) the same column is
    /// held to `mediaColumnWidth`, centred, with the artwork also kept short
    /// enough for the transport controls to stay on screen.
    private var stackedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // On a phone the pager is framed to the player's exact width,
                // so it can't report a different size while paging to the
                // next song and shove the column below it.
                artwork(width: stackedArtworkMaxWidth == nil ? playerSize.width : 0)
                    .frame(maxWidth: stackedArtworkMaxWidth)

                VStack(spacing: 0) {
                    nowPlayingControls
                    metaSection
                        .padding(.top, 14)
                }
                // Breathing room between the edge-to-edge cover and the title.
                .padding(.top, 24)
                .padding(.horizontal, PlayerStyle.pageSidePadding)
                .padding(.bottom, 8)
                // A song change swaps everything in here at once; laying it
                // out without animation keeps the controls from sliding.
                .transaction(value: song?.id) { $0.animation = nil }
            }
            .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
            // Pin the content to the scroll view's width. Something inside
            // (the paging artwork) proposed a wider ideal width, which pushed
            // the whole column ~24pt past the screen and swallowed the 20pt
            // side padding.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.always)
    }

    /// The episode has the inline chapters card.
    private var hasChapterUI: Bool { ChaptersCard.isShown(chapters: timelineStore.chapters) }

    /// Native-only tablet/Mac layout (Flutter has none): a landscape window
    /// wide enough for two columns keeps the artwork and transport on the
    /// left, always in view, and scrolls the lyrics, credits and "More like
    /// this" on the right.
    private var sideBySideContent: some View {
        let leftWidth = min(playerSize.width * 0.45, AdaptiveLayout.mediaColumnWidth)
        let artworkSide = max(
            Self.minimumSideBySideArtwork,
            min(leftWidth - PlayerStyle.pageSidePadding * 2, playerSize.height - Self.controlsReservedHeight)
        )
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    artwork(width: 0)
                        .frame(width: artworkSide)
                        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous))
                    nowPlayingControls
                        .padding(.top, 20)
                }
                .padding(.horizontal, PlayerStyle.pageSidePadding)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: leftWidth)

            ScrollView {
                metaSection
                    .padding(.horizontal, PlayerStyle.pageSidePadding)
                    .padding(.vertical, 20)
                    .readableContentWidth()
            }
            .scrollBounceBehavior(.always)
            .frame(maxWidth: .infinity)
        }
    }

    /// Height kept free under the artwork for the headline, seek bar,
    /// transport and queue/share row, so they stay on screen when a short
    /// window shrinks the artwork.
    private static let controlsReservedHeight: CGFloat = 320
    private static let minimumSideBySideArtwork: CGFloat = 200

    /// `nil` on a phone (edge to edge, as Flutter); on a wider window the
    /// artwork never takes more than 55% of the player's height.
    private var stackedArtworkMaxWidth: CGFloat? {
        guard AdaptiveLayout.isWide(playerSize.width) else { return nil }
        return max(Self.minimumSideBySideArtwork, playerSize.height * 0.55)
    }

    /// The ad takeover goes over the cover and nothing else: the title,
    /// progress bar and controls below it never change for an ad.
    /// `width` > 0 frames the pager to exactly that width (see
    /// `PlayerArtworkPager.width`); 0 lets the caller's frame size it.
    private func artwork(width: CGFloat) -> some View {
        PlayerAdOverlay(
            controller: playerAd,
            onOpen: { ad in adPacing.openAction(for: ad, coordinator: coordinator) },
            isUncovered: isPlayerUncovered
        ) {
            PlayerArtworkPager(queueController: queueController, width: width, video: videoContext)
        }
    }

    /// Headline through the queue/share row: everything that sits directly
    /// under the artwork.
    private var nowPlayingControls: some View {
        VStack(spacing: 0) {
            headline
            PlayerSeekBar(
                position: engine.currentPosition,
                duration: playbackDuration,
                barHeight: PlayerStyle.seekBarHeight,
                chapters: timelineStore.chapters
            ) { target in
                engine.seek(to: target)
            }
            .padding(.top, 16)
            PlayerTransportControls(engine: engine, queueController: queueController)
                .frame(height: PlayerStyle.playButtonDiameter)
                .padding(.top, 20)
            SleepTimerBadge(controller: sleepTimer)
                .padding(.top, 24)
            // The row's 44pt tap boxes carry 10pt of their own space above
            // the glyphs, so 14 here reads as the old 24.
            queueAndShareRow
                .padding(.top, sleepTimer.isActive ? 0 : 14)
        }
    }

    /// `_SongHeadline`: title (`titleMedium` w700) and artists
    /// (`bodyMedium`) marquees, then the favourite heart (24) and the
    /// add-to-playlist circle (24 with 8 padding). Fixed height: the two
    /// marquees are 24 + 21 and the buttons 40, so a missing or very long
    /// title/artist line never changes where the scrubber starts.
    private static let headlineHeight: CGFloat = 45

    private var headline: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(
                    text: song?.title ?? "",
                    typography: PlayerStyle.titleMediumBold,
                    color: PlayerStyle.white,
                    height: 24
                )
                MarqueeText(
                    text: subtitle,
                    typography: Typography.bodyMedium,
                    color: PlayerStyle.white,
                    height: 21
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            favouriteButton
            if song != nil, AppConfiguration.current.featureFlags.tipButtonEnabled, !offerings.isEmpty {
                Button { isTipSheetPresented = true } label: {
                    Image(systemName: "heart.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(PlayerStyle.white)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Support the Artist")
            }
            if song != nil {
                Button { isAddToPlaylistPresented = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(PlayerStyle.white)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to playlist")
            }
        }
        .frame(height: Self.headlineHeight)
    }

    /// `TipService.instance.sendTip` — the store's payment sheet takes over;
    /// outcomes surface as toasts, as in Flutter.
    private func sendTip(offering: Offering, note: String, song: Song) {
        Task {
            do {
                let confirmed = try await tipPurchases.sendTip(
                    offering: offering,
                    note: note,
                    creatorId: song.creator?.creatorId ?? song.songPrimaryArtists.compactMap(\.creatorId).first,
                    songId: song.id
                )
                if confirmed { toastCenter.show(String(localized: "Thank you for supporting the artist! 🙏")) }
            } catch let error as TipError {
                toastCenter.show(error.message)
            } catch let error as TipPurchaseManager.TipPurchaseError {
                toastCenter.show(error.displayMessage)
            } catch {
                toastCenter.show(String(localized: "Something went wrong while starting your tip"))
            }
        }
    }

    @ViewBuilder
    private var favouriteButton: some View {
        if let song {
            FavouriteToggleButton(isFavorited: song.isFavorited, size: 24, color: PlayerStyle.white) {
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

    /// `_QueueAndShareRow`: `spaceBetween` — queue, then share. iOS glyphs
    /// rather than the Flutter `menu.svg` hamburger and the three-dot share
    /// SVG: `list.bullet` is the "Up Next" glyph iOS users know from Music,
    /// and `square.and.arrow.up` is the system share icon. Both sit in the
    /// same 44pt box so the row's height never depends on which is shown.
    private var queueAndShareRow: some View {
        HStack(spacing: 0) {
            Button { isQueuePresented = true } label: {
                queueRowGlyph("list.bullet", alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue")

            Spacer()

            // Video / audio switch, just left of Share: only for an episode with a video.
            // Both glyphs sit on their box's trailing edge, so the gap between them is
            // the 44 pt box less the glyph, about 24 pt, like the Flutter row.
            if song?.hasVideo == true {
                MediaModeToggle(isShowingVideo: videoMode.showsVideo, isLocked: isVideoLocked) {
                    if isVideoLocked {
                        // As the song menu does for a locked download: leave the player, open the plans.
                        coordinator.dismissFullScreen()
                        coordinator.push(.subscriptionPlans)
                    } else {
                        videoMode.toggle()
                    }
                }
            }

            Button { isSharePresented = true } label: {
                queueRowGlyph("square.and.arrow.up", alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
            .opacity(song == nil ? 0 : 1)
            .disabled(song == nil)
        }
    }

    private func queueRowGlyph(_ systemName: String, alignment: Alignment) -> some View {
        Image(systemName: systemName)
            .font(.system(size: PlayerStyle.queueRowGlyphSize, weight: .medium))
            .foregroundStyle(PlayerStyle.white)
            .frame(width: PlayerStyle.queueRowBox, height: PlayerStyle.queueRowBox, alignment: alignment)
            .contentShape(Rectangle())
    }

    /// `SongMetaDataUi`: lyrics card, then (not ported: creator card and
    /// credits) a 16pt gap, "Description" (`bodyMedium`) and the expandable
    /// description (`bodySmall`).
    @ViewBuilder
    private var metaSection: some View {
        if let song {
            VStack(alignment: .leading, spacing: 0) {
                // An episode's chapters sit inline under the controls (the mapper keeps none for fewer than two).
                if hasChapterUI {
                    ChaptersCard(
                        chapters: timelineStore.chapters,
                        position: engine.currentPosition,
                        duration: playbackDuration,
                        isPlaying: engine.status == .playing
                    ) { chapter in
                        // A row seeks and plays, as the Flutter chapter list does.
                        engine.seek(to: Double(chapter.startMs) / 1000)
                        engine.resume()
                    }
                }
                // Rule R1: the read-along shows only for a ready transcript; otherwise this column is as before.
                if timelineStore.hasReadAlong {
                    if timelineStore.hasMultipleSpeakers {
                        NowSpeakingChip(store: timelineStore)
                    }
                    ReadAlongCard(store: timelineStore) {
                        coordinator.pushInPlayer(.episodeTranscript)
                    }
                }
                PlayerLyricsPreviewCard(song: song, currentPosition: engine.currentPosition) {
                    coordinator.pushInPlayer(.lyrics(songTitle: song.title ?? String(localized: "Lyrics")))
                }
                // Creator card, credits, then the description, then the
                // "More like this" rail (`SongMetaDataUi` order).
                SongMetaSections(
                    songId: song.id,
                    excludeId: RecentlyPlayedSyncer.sourceID(from: queueController.queue?.source.id),
                    middle: AnyView(
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Description")
                                .typography(Typography.bodyMedium)
                                .foregroundStyle(PlayerStyle.white)
                            PlayerExpandableText(
                                text: song.description ?? "",
                                chapterStartsMs: timelineStore.chapters.map(\.startMs),
                                onTimestampTap: { milliseconds in
                                    // A tapped timestamp seeks and plays, like a row of the chapters sheet.
                                    engine.seek(to: Double(milliseconds) / 1000)
                                    engine.resume()
                                }
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `showAddToPlaylistSheet` hosted by the player's `add_circle_outline`
/// button: the song menu's own playlist picker, driven by its view model.
private struct PlayerAddToPlaylistSheet: View {
    @State private var viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    init(song: Song, onOutcome: @escaping (SongMenuOutcome) -> Void) {
        _viewModel = State(initialValue: SongMenuViewModel(song: song))
        self.onOutcome = onOutcome
    }

    var body: some View {
        AddToPlaylistView(viewModel: viewModel, onOutcome: onOutcome)
    }
}

/// `ExpandableText` (`verse_unit_ui.dart`): `bodySmall`, three lines with a
/// "Read more" / "Read less" toggle shown only when the text overflows.
/// With `onReadMore` (the creator card's bio, `CreatorMetaUi`), "Read more"
/// runs that instead of expanding in place, as Flutter's `onTap` does.
///
/// With `chapterStartsMs`, a timestamp in the text that equals a chapter's start
/// (`DescriptionTimestamps`) is drawn as a blue link, and tapping it calls
/// `onTimestampTap` with its time in milliseconds. The link carries a private
/// URL scheme that this view handles itself. With no chapters the text is
/// plain, exactly as before.
struct PlayerExpandableText: View {
    let text: String
    var maxLines: Int = 3
    var token: TypographyToken = Typography.bodySmall
    var color: Color = PlayerStyle.white
    var linkColor: Color = PlayerStyle.white
    var onReadMore: (() -> Void)? = nil
    var chapterStartsMs: [Int] = []
    var onTimestampTap: ((Int) -> Void)? = nil

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    private var overflows: Bool { fullHeight > limitedHeight + 1 }

    /// The text with its chapter timestamps as links, or `nil` when none match.
    private var linkedText: AttributedString? {
        let links = DescriptionTimestamps.links(in: text, chapterStartsMs: chapterStartsMs)
        guard !links.isEmpty else { return nil }
        var result = AttributedString(text)
        for link in links {
            guard let range = Range(link.range, in: result),
                  let url = DescriptionTimestamps.url(forMilliseconds: link.milliseconds)
            else { continue }
            result[range].link = url
            result[range].foregroundColor = PlayerStyle.timestampLink
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            visibleText
                .typography(token)
                .foregroundStyle(color)
                .tint(PlayerStyle.timestampLink)
                .lineLimit(isExpanded ? nil : maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Text(text)
                        .typography(token)
                        .lineLimit(maxLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(HeightReader { limitedHeight = $0 })
                )
                .background(
                    Text(text)
                        .typography(token)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(HeightReader { fullHeight = $0 })
                )
            if overflows {
                Button {
                    if let onReadMore { onReadMore() } else { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Read less" : "Read more")
                        .typography(TypographyToken(size: token.size, weight: .bold, lineHeightMultiple: 1.5))
                        .foregroundStyle(linkColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension PlayerExpandableText {
    /// What the reader sees. The two hidden copies that measure the height stay
    /// plain, since a link does not change the layout.
    @ViewBuilder
    fileprivate var visibleText: some View {
        if let linkedText {
            Text(linkedText)
                .environment(\.openURL, OpenURLAction { url in
                    guard let milliseconds = DescriptionTimestamps.milliseconds(from: url) else {
                        return .systemAction
                    }
                    onTimestampTap?(milliseconds)
                    return .handled
                })
        } else {
            Text(text)
        }
    }
}

private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onChange(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, newValue in onChange(newValue) }
        }
    }
}
