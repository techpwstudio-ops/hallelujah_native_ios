import SwiftUI

/// The song's "more" menu (`showSongMenu`, `lib/sheets/song/song_menu_sheet.dart`).
/// One sheet that swaps between its menu and the pages it opens (share,
/// credits, report, add to playlist) — nested sheets inside a sheet are
/// fragile in SwiftUI, and Dart's own flow is menu → close → open the next.
///
/// The host supplies navigation and toasts through `onOutcome`; this view only
/// renders and routes taps to `SongMenuViewModel`.
struct SongMenuSheet: View {
    @State private var viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    @Environment(\.appTheme) private var theme

    init(song: Song, userPlaylistID: String? = nil, onOutcome: @escaping (SongMenuOutcome) -> Void) {
        _viewModel = State(initialValue: SongMenuViewModel(song: song, userPlaylistID: userPlaylistID))
        self.onOutcome = onOutcome
    }

    var body: some View {
        switch viewModel.page {
        case .menu: menu
        case .share: shareContent
        case .credits: SongCreditsView(viewModel: viewModel)
        case .report: ReportSongView(viewModel: viewModel, onOutcome: onOutcome)
        case .addToPlaylist: AddToPlaylistView(viewModel: viewModel, onOutcome: onOutcome)
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SongMenuRow(systemImage: "square.and.arrow.up", title: "Share") {
                    viewModel.page = .share
                }
                if viewModel.isInUserPlaylist {
                    SongMenuRow(systemImage: "minus.circle", title: "Remove from playlist") {
                        run { await viewModel.removeFromPlaylist() }
                    }
                }
                SongMenuRow(
                    systemImage: viewModel.song.isFavorited ? "heart.fill" : "heart",
                    title: viewModel.song.isFavorited ? "Remove from favorites" : "Add to favorites"
                ) {
                    run { await viewModel.toggleFavourite() }
                }
                SongMenuRow(systemImage: "plus", title: "Add to playlist") {
                    viewModel.page = .addToPlaylist
                }
                SongMenuRow(systemImage: "text.badge.plus", title: "Add to queue") {
                    run { await viewModel.addToQueue() }
                }
                SongMenuRow(systemImage: "person.crop.circle", title: "Go to artist") {
                    Task {
                        if let id = await viewModel.resolveArtistID() {
                            onOutcome(.goToArtist(id))
                        } else {
                            onOutcome(.message(String(localized: "Artist not available")))
                        }
                    }
                }
                SongMenuRow(systemImage: "moon.zzz", title: "Sleep timer") {
                    run { await viewModel.requestSleepTimer() }
                } trailing: {
                    if viewModel.blocksPremium {
                        GoPremiumBadge()
                    } else if let left = viewModel.sleepTimeLeftText {
                        Text(left)
                            .italic()
                            .typography(Typography.bodyLarge)
                            .foregroundStyle(Color(red: 1, green: 0.714, blue: 0.106))
                    }
                }
                SongMenuRow(systemImage: "person.2", title: "View credits") {
                    viewModel.page = .credits
                }
                SongMenuRow(systemImage: viewModel.downloadSystemImage, title: LocalizedStringKey(viewModel.downloadTitle)) {
                    run { await viewModel.download() }
                } trailing: {
                    if viewModel.blocksPremium { GoPremiumBadge() }
                }
                SongMenuRow(systemImage: "flag", title: "Report") {
                    viewModel.page = .report
                }
                SongMenuRow(systemImage: "stop.fill", title: "Stop") {
                    onOutcome(viewModel.stopPlayback())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
        .task { await viewModel.loadPremium() }
    }

    private var shareContent: some View {
        ShareSheetView(
            target: .song(id: viewModel.song.id),
            title: viewModel.song.title ?? "",
            subtitle: nil,
            artworkURL: ArtworkURLResolver().resolve(
                path: viewModel.song.displayImage,
                variant: .lg,
                allowedVariants: viewModel.song.displayImageVariants
            )
        )
    }

    private func run(_ action: @escaping () async -> SongMenuOutcome) {
        Task { onOutcome(await action()) }
    }
}
