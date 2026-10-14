import SwiftUI
import UIKit

/// Ports `PlayingFromTitle` (`lib/widgets/player/playing_from_title.dart`):
/// the player app bar's title. A container-backed queue shows
/// "PLAYING FROM <KIND>" (9pt, w600, 0.9 tracking, white @ 60%) over the
/// container's name (marquee, `titleMedium` w600); playback with no container
/// (home, search, downloads, favourites, invites) falls back to the plain
/// one-line title. Tapping the source to open its page is not ported (needs
/// the per-kind navigation the Flutter route table provides).
struct PlayingFromTitle: View {
    let queueController: QueueController
    let song: Song?

    private var sourceLabel: String? {
        guard let source = queueController.queue?.source else { return nil }
        let name = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, source.id != nil else { return nil }
        switch source.playerType {
        case .companyPlaylist, .userPlaylist: return "PLAYING FROM PLAYLIST"
        case .album: return "PLAYING FROM ALBUM"
        case .season: return "PLAYING FROM SEASON"
        case .genre: return "PLAYING FROM GENRE"
        case .creator: return (song?.isEpisode ?? false) ? "PLAYING FROM PODCAST" : "PLAYING FROM ARTIST"
        case .home, .search, .download, .favourite, .invite: return nil
        }
    }

    private var name: String {
        let title = queueController.queue?.source.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return song?.title ?? ""
    }

    private static let maxWidth: CGFloat = 220

    /// `MyMarquee` renders a plain, centred `Text` when the line fits and only
    /// scrolls when it does not — measured here so a short title stays
    /// centred in the bar like Flutter's.
    private var nameFits: Bool {
        let font = UIFont(name: "HelveticaNeue-Medium", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .semibold)
        return (name as NSString).size(withAttributes: [.font: font]).width <= Self.maxWidth
    }

    @ViewBuilder
    private var nameLine: some View {
        if nameFits {
            Text(name)
                .typography(PlayerStyle.titleMediumSemibold)
                .foregroundStyle(PlayerStyle.white)
                .lineLimit(1)
        } else {
            MarqueeText(
                text: name,
                typography: PlayerStyle.titleMediumSemibold,
                color: PlayerStyle.white,
                height: sourceLabel == nil ? 24 : 20
            )
        }
    }

    var body: some View {
        if let label = sourceLabel {
            VStack(spacing: 2) {
                Text(label)
                    .typography(PlayerStyle.playingFromLabel)
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
                    .lineLimit(1)
                nameLine
            }
            .frame(maxWidth: Self.maxWidth)
        } else {
            nameLine
                .frame(maxWidth: Self.maxWidth)
        }
    }
}
