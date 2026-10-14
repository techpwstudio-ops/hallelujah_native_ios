import SwiftUI

/// T35 — the expanded player, replacing `FullScreenDestinationView`'s
/// `.player` placeholder. Ports `AudioPlayerScreen`
/// (`lib/views/home/audio_player_screen.dart`), deliberately scoped to
/// exactly what T35's own roadmap text names ("artwork, seek bar,
/// transport, like, download, share, queue, lyrics entry, output picker")
/// rather than that screen's full surface. Real Dart sections NOT ported
/// here, each for a specific reason rather than an oversight:
/// - **Ads**: now real (T69). `body` below branches to `AdBreakView`
///   whenever `adPacing.isAdBreak` is true, replacing this screen's content
///   outright rather than overlaying it — the same way Dart's own
///   `AudioPlayerScreen` swaps its body for `AdBreakScreen`. No dismiss
///   affordance is shown in that branch, mirroring `_AdBreakAppBar`'s own
///   doc comment ("a break is meant to be sat through, not backed out of on
///   a whim"); Dart's own escape hatch for it — two system-back presses
///   within ~2s, deliberately advertised nowhere on screen — isn't ported,
///   since `.fullScreenCover` has no equivalent gesture to hang it off and
///   T69's own done criterion names cadence and premium gating, not this
///   edge case. `SleepTimerBadge` is still out of scope: grepped against
///   every one of progress.md's 76 tasks, zero hits, same status as the
///   legacy non-glass mini player (T34).
/// - Creator meta / credits / description / related-content rail: not
///   named in T35's own roadmap text; `RelatedContentRail` also needs a
///   recommendation-fetch backend call this codebase doesn't have yet
///   (same gap T33 already flagged for automatic queue hand-off).
/// - **Share**: now real (T68 — Sharing). `shareButton` below presents
///   `ShareSheetView`, which mints the link via `DeepLinkService.songShareLink`
///   — the native `DeepLinkService.songShare(id:)` counterpart to Dart's
///   `DeepLinkService.instance.create(songId)` this comment used to say
///   didn't exist yet.
///
/// **Download** is real now (T46 — Download engine): this used to be listed
/// above as deliberately NOT ported, since no native download/task-tracking
/// infrastructure existed yet. Unlike Dart, which puts it behind the "..."
/// menu (still out of scope here — see Share above, and the "..." menu
/// itself still doesn't exist anywhere in this app), this ports it as a
/// direct action-row icon instead, following T44's `favouriteButton`
/// precedent below for a single-song action: a plain button wired straight
/// to an engine call, no menu.
///
/// Queue and lyrics ARE real entry points, just not full screens of their
/// own yet. Queue reuses the already-existing `PlayerRoute.queue` push
/// (built by a prior pass anticipating this) rather than the bottom sheet
/// Dart itself uses (`showQueueSheet`) — one presentation mechanism for
/// that destination, not two competing ones; T37 (Queue screen) replaces
/// its placeholder later. Lyrics gets a real inline preview card
/// (`PlayerLyricsPreviewCard`, matching Dart's on-screen
/// `SongLyricsDetails` exactly) plus a button pushing the existing
/// `PlayerRoute.lyrics` placeholder (T36's screen to fill in).
///
/// **Tip (T64)**: `tipButton` is the native port of
/// `audio_player_screen.dart`'s own tip `InkWell` + `showTipToArtistSheet`
/// call site — except Dart wraps that entire call site in `if (false)`,
/// permanently unreachable in the shipping app (confirmed by reading the
/// full `if`/child block there; no other call site of
/// `showTipToArtistSheet` exists anywhere in the Dart source). This port
/// wires it live/reachable instead of also dark-launching it: T64's own done
/// criterion ("tip purchase completes") requires a reachable UI to exercise
/// the mechanism, and Dart's own disabled state serves no purpose here that
/// isn't better served by a working feature — flagged as a deliberate
/// judgment call, not a silent deviation.
struct FullPlayerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var favouriteRepository: any FavouriteRepository = DependencyContainer.current.resolve()
    @State private var premiumGate: PremiumGate = DependencyContainer.current.resolve()
    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()
    @State private var keyValueStore: any KeyValueStoring = DependencyContainer.current.resolve()
    @State private var tipPurchaseManager: TipPurchaseManager = DependencyContainer.current.resolve()
    @State private var adPacing: AdPacingController = DependencyContainer.current.resolve()
    @State private var isRemoveDownloadConfirmationPresented = false
    @State private var isSharePresented = false
    @State private var isTipSheetPresented = false

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
        // T46 — same destructive-confirmation shape as
        // `UserPlaylistDetailView`'s delete dialog: a two-button sheet, no
        // separate presented-item state, since the dialog is modal and
        // `song` can't change out from under it while it's up.
        .confirmationDialog(
            "Remove this download?",
            isPresented: $isRemoveDownloadConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let song {
                    downloadEngine.deleteDownload(songID: song.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
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
        .appSheet(isPresented: $isTipSheetPresented) {
            if let song {
                TipDonationSheet(artistName: song.creator?.name ?? song.primaryArtists) { amount, note in
                    sendTip(amount: amount, note: note, creatorId: song.creator?.creatorId, songId: song.id)
                }
            }
        }
    }

    private var playerContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                PlayerArtworkPager(queueController: queueController)
                    .padding(.horizontal, Spacing.md)

                headline

                VStack(spacing: Spacing.md) {
                    SeekBar(
                        position: engine.currentPosition,
                        duration: engine.currentItemDuration ?? TimeInterval(song?.duration ?? 0)
                    ) { target in
                        engine.seek(to: target)
                    }
                    PlayerTransportControls(engine: engine, queueController: queueController)
                }
                .padding(.horizontal, Spacing.md)

                actionRow

                if let song {
                    PlayerLyricsPreviewCard(song: song, currentPosition: engine.currentPosition) {
                        coordinator.pushInPlayer(.lyrics(songTitle: song.title ?? ""))
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxl)
        }
        .background(theme.color(.backgroundPrimary).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { coordinator.dismissFullScreen() } label: {
                    theme.icon(.chevronDown)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            }
            ToolbarItem(placement: .principal) {
                playingFromHeader
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var playingFromHeader: some View {
        if let title = queueController.queue?.source.title {
            VStack(spacing: 0) {
                Text("Playing from")
                    .typography(Typography.labelSmall)
                    .foregroundStyle(theme.color(.textSecondary))
                Text(title)
                    .typography(Typography.labelLarge)
                    .foregroundStyle(theme.color(.textPrimary))
            }
        }
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: song?.title ?? "", typography: Typography.titleLarge, color: theme.color(.textPrimary), height: 26)
                MarqueeText(text: subtitle, typography: Typography.bodyMedium, color: theme.color(.textSecondary), height: 20)
            }
            Spacer(minLength: 0)
            favouriteButton
            tipButton
        }
        .padding(.horizontal, Spacing.md)
    }

    /// `FavouriteButton(song:, size: 24)` (`audio_player_screen.dart`'s
    /// `_SongHeadline`) — no explicit `color:` there, so this leaves
    /// `FavouriteToggleButton.color` at its own default (`textPrimary`),
    /// matching Dart's own `FavouriteButton{color = Colors.white}` default.
    @ViewBuilder
    private var favouriteButton: some View {
        if let song {
            FavouriteToggleButton(isFavorited: song.isFavorited, size: 24) {
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

    /// `TipPayIcon` (`audio_player_screen.dart`'s `_SongHeadline`) — see this
    /// type's own doc comment for why this is wired live despite Dart's own
    /// call site being dead code. A plain SF Symbol literal rather than a new
    /// `IconToken` case, same precedent `ShareSheetView`'s own per-platform
    /// icons already use (`IconToken.swift` has no suitable "tip"/"gift"
    /// case, and is a protected file this task may not edit directly).
    @ViewBuilder
    private var tipButton: some View {
        if song != nil {
            Button {
                isTipSheetPresented = true
            } label: {
                Image(systemName: "gift")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)
        }
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.xl) {
            Button { coordinator.pushInPlayer(.queue) } label: {
                theme.icon(.queue)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)

            Spacer()

            downloadButton

            shareButton

            AudioRoutePickerView(
                tintColor: UIColor(theme.color(.textPrimary)),
                activeTintColor: UIColor(theme.color(.brandPrimary))
            )
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, Spacing.md)
    }

    /// T46 — Download engine: a plain icon button wired straight to
    /// `DownloadEngine`, the same "single icon, straight to the
    /// engine/repository, no menu" shape `favouriteButton` above already
    /// established for T44. Three visual states, read straight off
    /// `DownloadEngine`: a plain down-arrow when the song isn't downloaded,
    /// a small spinner while `downloadEngine.tasks[song.id]` is
    /// `.queued`/`.downloading`/`.paused`, and the same glyph in its filled
    /// SF Symbol variant (`.symbolVariant(.fill)` — no new `IconToken` case
    /// needed; `.download` already covers both, matching that enum's own
    /// "closest system equivalent" posture) once `isDownloaded` is true. A
    /// `.failed` task reads as "not downloaded" and a tap re-enqueues —
    /// this button only exposes the two tap actions the download contract
    /// names for the player (enqueue, remove); a dedicated retry affordance
    /// belongs to the Downloads management screen T46 also builds.
    @ViewBuilder
    private var downloadButton: some View {
        if let song {
            switch downloadButtonState(for: song) {
            case .downloaded:
                Button {
                    isRemoveDownloadConfirmationPresented = true
                } label: {
                    theme.icon(.download)
                        .symbolVariant(.fill)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.color(.brandPrimary))
                }
                .buttonStyle(.plain)
            case .inProgress:
                ProgressView()
                    .frame(width: 20, height: 20)
            case .notDownloaded:
                Button {
                    Task { await startDownload(song) }
                } label: {
                    theme.icon(.download)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.color(.textPrimary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if song != nil {
            Button {
                isSharePresented = true
            } label: {
                theme.icon(.share)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)
        }
    }

    private enum DownloadButtonState {
        case notDownloaded
        case inProgress
        case downloaded
    }

    private func downloadButtonState(for song: Song) -> DownloadButtonState {
        if downloadEngine.isDownloaded(songID: song.id) { return .downloaded }
        switch downloadEngine.tasks[song.id]?.state {
        case .queued, .downloading, .paused: return .inProgress
        case .failed, .completed, nil: return .notDownloaded
        }
    }

    /// Enqueues at the user's current effective playback quality —
    /// `AudioQualitySelector.targetQuality()` (plan cap × network cap; the
    /// same selector `AppComposition` builds its own instance of for
    /// `PlaybackAnalyticsRecorder` — stateless, so a fresh instance here is
    /// equivalent, same reasoning already used there).
    private func startDownload(_ song: Song) async {
        // T65 — downloads are premium-only (`song_menu_sheet.dart`). A free
        // listener is sent to the plans screen instead, the same redirect.
        guard await premiumGate.allows(.downloads) else {
            coordinator.dismissFullScreen()
            coordinator.push(.subscriptionPlans)
            return
        }
        let selector = AudioQualitySelector(
            keyValueStore: keyValueStore,
            batteryMonitor: UIDeviceBatteryLevelMonitor(),
            connectivityType: NWPathConnectivityTypeProvider()
        )
        let quality = await selector.targetQuality()
        await downloadEngine.enqueue(song: song, quality: quality)
    }

    /// `TipService.instance.sendTip(...)` (`audio_player_screen.dart`'s
    /// `onSend` callback) — fire-and-forget from the UI's perspective, same
    /// as Dart: `TipDonationSheet` has already dismissed itself by the time
    /// this runs, and the only observable outcome is the toast below.
    private func sendTip(amount: Int, note: String, creatorId: String?, songId: String?) {
        Task {
            do {
                if try await tipPurchaseManager.sendTip(amount: amount, note: note, creatorId: creatorId, songId: songId) {
                    toastCenter.show("Thank you for supporting the artist! 🙏")
                }
            } catch {
                toastCenter.show(Self.tipErrorMessage(for: error))
            }
        }
    }

    private static func tipErrorMessage(for error: any Error) -> String {
        if let error = error as? TipPurchaseManager.TipPurchaseError { return error.displayMessage }
        if let error = error as? TipError { return error.message }
        return "Something went wrong. Please try again."
    }
}
