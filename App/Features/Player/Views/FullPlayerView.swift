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
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var playerAd: PlayerAdController = DependencyContainer.current.resolve()
    @State private var sleepTimer: SleepTimerController = DependencyContainer.current.resolve()
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
            PlayerArtworkPager(queueController: queueController, width: width)
        }
    }

    /// Headline through the queue/share row: everything that sits directly
    /// under the artwork.
    private var nowPlayingControls: some View {
        VStack(spacing: 0) {
            headline
            PlayerSeekBar(
                position: engine.currentPosition,
                duration: engine.currentItemDuration ?? TimeInterval(song?.duration ?? 0),
                barHeight: PlayerStyle.seekBarHeight
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
        HStack {
            Button { isQueuePresented = true } label: {
                queueRowGlyph("list.bullet", alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue")

            Spacer()

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
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(PlayerStyle.white)
            .frame(width: 44, height: 44, alignment: alignment)
            .contentShape(Rectangle())
    }

    /// `SongMetaDataUi`: lyrics card, then (not ported: creator card and
    /// credits) a 16pt gap, "Description" (`bodyMedium`) and the expandable
    /// description (`bodySmall`).
    @ViewBuilder
    private var metaSection: some View {
        if let song {
            VStack(alignment: .leading, spacing: 0) {
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
                            PlayerExpandableText(text: song.description ?? "")
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
struct PlayerExpandableText: View {
    let text: String
    var maxLines: Int = 3
    var token: TypographyToken = Typography.bodySmall
    var color: Color = PlayerStyle.white
    var linkColor: Color = PlayerStyle.white
    var onReadMore: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    private var overflows: Bool { fullHeight > limitedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .typography(token)
                .foregroundStyle(color)
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
