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
/// Not ported (data or services this codebase lacks): the creator card,
/// credits, the related-content rail, the ad companion banner and the
/// artwork pager's overscroll-to-skip gesture.
struct FullPlayerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var sleepTimer: SleepTimerController = DependencyContainer.current.resolve()
    @State private var isSharePresented = false
    @State private var isQueuePresented = false
    @State private var isAddToPlaylistPresented = false
    @State private var isSleepTimerSheetPresented = false
    @State private var menuSong: Song?

    private var song: Song? { engine.currentSong }

    private var subtitle: String {
        [song?.primaryArtists, song?.featuredArtists]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

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
        .appSheet(isPresented: $isSharePresented) {
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
                    default:
                        isAddToPlaylistPresented = false
                    }
                }
            }
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
        ScrollView {
            VStack(spacing: 0) {
                PlayerArtworkPager(queueController: queueController)

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
                        .padding(.top, 20)
                    SleepTimerBadge(controller: sleepTimer)
                        .padding(.top, 24)
                    queueAndShareRow
                        .padding(.top, sleepTimer.isActive ? 0 : 24)
                    metaSection
                        .padding(.top, 24)
                }
                .padding(.top, 20)
                .padding(.horizontal, PlayerStyle.pageSidePadding)
                .padding(.bottom, 8)
            }
        }
        .scrollBounceBehavior(.always)
        .background(PlayerStyle.black.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { coordinator.dismissFullScreen() } label: {
                    theme.icon(.back)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PlayerStyle.white)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .principal) {
                PlayingFromTitle(queueController: queueController, song: song)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if song != nil {
                    Button { menuSong = song } label: {
                        // `Icons.more_vert`.
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 22))
                            .foregroundStyle(PlayerStyle.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(PlayerStyle.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// `_SongHeadline`: title (`titleMedium` w700) and artists
    /// (`bodyMedium`) marquees, then the favourite heart (24) and the
    /// add-to-playlist circle (24 with 8 padding).
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

    /// `_QueueAndShareRow`: `spaceBetween` — the queue `menu.svg` glyph, then
    /// the share glyph.
    private var queueAndShareRow: some View {
        HStack {
            Button { isQueuePresented = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 24))
                    .foregroundStyle(PlayerStyle.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue")

            Spacer()

            if song != nil {
                Button { isSharePresented = true } label: {
                    theme.icon(.share)
                        .font(.system(size: 24))
                        .foregroundStyle(PlayerStyle.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
            }
        }
    }

    /// `SongMetaDataUi`: lyrics card, then (not ported: creator card and
    /// credits) a 16pt gap, "Description" (`bodyMedium`) and the expandable
    /// description (`bodySmall`).
    @ViewBuilder
    private var metaSection: some View {
        if let song {
            VStack(alignment: .leading, spacing: 0) {
                PlayerLyricsPreviewCard(song: song, currentPosition: engine.currentPosition) {
                    coordinator.pushInPlayer(.lyrics(songTitle: song.title ?? "Lyrics"))
                }
                Text("Description")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(PlayerStyle.white)
                    .padding(.top, 16)
                PlayerExpandableText(text: song.description ?? "")
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
struct PlayerExpandableText: View {
    let text: String
    var maxLines: Int = 3

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    private var overflows: Bool { fullHeight > limitedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .typography(Typography.bodySmall)
                .foregroundStyle(PlayerStyle.white)
                .lineLimit(isExpanded ? nil : maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Text(text)
                        .typography(Typography.bodySmall)
                        .lineLimit(maxLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(HeightReader { limitedHeight = $0 })
                )
                .background(
                    Text(text)
                        .typography(Typography.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(HeightReader { fullHeight = $0 })
                )
            if overflows {
                Button { isExpanded.toggle() } label: {
                    Text(isExpanded ? "Read less" : "Read more")
                        .typography(TypographyToken(size: 12, weight: .bold, lineHeightMultiple: 1.5))
                        .foregroundStyle(PlayerStyle.white)
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
