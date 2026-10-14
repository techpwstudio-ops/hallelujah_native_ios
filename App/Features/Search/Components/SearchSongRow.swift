import SwiftUI

/// Ports `SongSearchItem` / `_SongSearchTile` (`lib/widgets/song/song_search_item.dart`):
/// 52pt thumbnail (16:9 wide for an episode), radius 8, 12pt gap, 16/6
/// padding. Title `titleSmall` w500 white (w700 yellow while playing),
/// 3pt gap, subtitle `"<primary> • <featured> • Music|Episode"` in
/// `bodySmall` white60. The only trailing control is the recent-search
/// close button — Flutter shows no song menu on a search row.
struct SearchSongRow: View {
    let song: Song
    var isPlaying: Bool = false
    var onRemove: (() -> Void)?
    /// `AddToPlaylistCheckBox` — non-nil shows the picker checkbox.
    var isChecked: Bool?
    let onTap: () -> Void

    static let thumbnailSize: CGFloat = 52

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: song.image, variant: .sm, allowedVariants: song.imageVariants)
    }

    private var thumbWidth: CGFloat {
        song.isEpisode ? Self.thumbnailSize * (16.0 / 9.0) : Self.thumbnailSize
    }

    private var subtitle: String {
        let artists = [song.primaryArtists, song.featuredArtists]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: parityDotSign)
        let typeLabel = song.type == "music" ? "Music" : "Episode"
        return artists.isEmpty ? typeLabel : "\(artists)\(parityDotSign)\(typeLabel)"
    }

    var body: some View {
        HStack(spacing: Dimens.spacing12) {
            ZStack {
                ArtworkView(
                    url: resolvedArtwork,
                    width: thumbWidth,
                    height: Self.thumbnailSize,
                    cornerRadius: Dimens.cornerRadius
                )
                if isPlaying {
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: thumbWidth, height: Self.thumbnailSize)
                    Image(systemName: "waveform")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white)
                }
            }

            ParityRowText(title: song.title ?? "", subtitle: subtitle, isActive: isPlaying)

            Spacer(minLength: 0)

            if let isChecked {
                ParityCheckbox(isChecked: isChecked)
            } else if let onRemove {
                ParityCloseButton(action: onRemove)
            }
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
