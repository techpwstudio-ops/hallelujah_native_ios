import SwiftUI

/// Ports `SongListItem` -> `MusicListItem` / `EpisodeListItem` ->
/// `BaseMediaListTile` (`lib/widgets/song/*`): 12/8 tile padding; artwork
/// 56pt tall, radius 4, 56 wide for music and 56*16/9 for an episode; 14pt
/// gap; title `titleMedium` capitalised (w600, bold yellow while it is the
/// playing song); 4pt gap; subtitle `bodySmall` white70 — the genre name for
/// music, the formatted duration for an episode. Episodes add a 12pt-gapped
/// block under the row: description (2 lines, white60), 6pt gap, release date
/// `dd/MM/yyyy` (white54). Trailing is the `more_vert` song menu
/// (`MediaTrailingSection`). Tapping the tile plays the song.
struct CreatorSongRow: View {
    let song: Song
    var userPlaylistID: String?
    var showsMenu: Bool = true
    /// Replaces the genre/duration subtitle (e.g. a downloaded snapshot that
    /// only carries a genre name).
    var subtitleOverride: String?
    /// Extra content under the subtitle (`DownloadProgressWidget`).
    var statusView: AnyView?
    var onTap: () -> Void = {}

    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var menuSong: Song?

    private static let thumbnailSize: CGFloat = 56
    private static let titleStyle = TypographyToken(size: 16, weight: .semibold, lineHeightMultiple: 1.4)
    private static let titleActiveStyle = TypographyToken(size: 16, weight: .bold, lineHeightMultiple: 1.4)

    private var isActive: Bool { queueController.queue?.currentSong?.id == song.id }
    private var isMusic: Bool { song.type == "music" }

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: song.displayImage,
            variant: .sm,
            allowedVariants: song.displayImageVariants
        )
    }

    private var subtitle: String {
        if let subtitleOverride { return subtitleOverride }
        if isMusic { return song.primaryGenre?.name ?? "" }
        // An episode without a duration yet shows nothing rather than "0 min".
        guard let duration = song.duration, duration > 0 else { return "" }
        return parityDurationText(duration)
    }

    private var episodeDescription: String {
        (song.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(
                    url: resolvedArtwork,
                    width: isMusic ? Self.thumbnailSize : Self.thumbnailSize * 16 / 9,
                    height: Self.thumbnailSize,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
                Spacer().frame(width: 14)

                VStack(alignment: .leading, spacing: 0) {
                    Text((song.title ?? "").parityCapitalized)
                        .typography(isActive ? Self.titleActiveStyle : Self.titleStyle)
                        .foregroundStyle(isActive ? ParityColor.yellow500 : Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Spacer().frame(height: 4)
                        Text(subtitle)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(ParityColor.white70)
                    }
                    if let statusView {
                        statusView.padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)

                if showsMenu {
                    Button { menuSong = song } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 24))
                            .foregroundStyle(Color.white)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
            }

            if !isMusic, !episodeDescription.isEmpty || song.releaseDate != nil {
                Spacer().frame(height: 12)
                VStack(alignment: .leading, spacing: 6) {
                    if !episodeDescription.isEmpty {
                        Text(episodeDescription)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(ParityColor.white60)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    if song.releaseDate != nil {
                        Text(parityDateText(song.releaseDate))
                            .typography(Typography.bodySmall)
                            .foregroundStyle(ParityColor.white54)
                    }
                }
            }
        }
        .padding(.horizontal, Dimens.paddingMedium)
        .padding(.vertical, Dimens.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .songMenu(song: $menuSong, userPlaylistID: userPlaylistID)
    }
}
