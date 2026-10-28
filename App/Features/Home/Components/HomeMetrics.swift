import SwiftUI

/// Geometry and colours the Flutter home feed spells as literals or as
/// public constants on its widgets (`HomeSongRowUi.railHeight`,
/// `HomeEpisodeItemUi`'s 256-wide card, `ColorTheme.white50`, …). Kept in one
/// place inside the Home feature so a native card and its skeleton are built
/// from the same numbers — exactly what the Dart side does (see
/// `home_section_shimmer.dart`'s "a skeleton that has its own copy of these
/// numbers silently stops matching" note). Shared token files are untouched;
/// where `Dimens` already has the Flutter value it is used directly.
enum HomeMetrics {
    /// The shared height of every 98-cover rail (`HomeSongRowUi.railHeight`).
    static let railHeight: CGFloat = 144
    /// Square rail cover (`HomeSongRowUi.coverSize`).
    static let coverSize: CGFloat = 98
    /// `HomeCardTitle.coverGap` = `Dimens.spacing6`.
    static let coverToTitleGap: CGFloat = Dimens.spacing6
    /// Trailing gap after every rail card (`pOnly(right: Dimens.horizontalSpacing)`).
    static let cardSpacing: CGFloat = Dimens.horizontalSpacing
    /// `Dimens.episodeHomeRowUnitWidth` — the wide 16:9 episode card.
    static let episodeCardWidth: CGFloat = 256
    /// `Dimens.episodeThumbnailHeight`.
    static let episodeCardHeight: CGFloat = 144
    /// `CreatorGridItem.avatarSize` / `avatarToNameGap`.
    static let creatorAvatarSize: CGFloat = 80
    static let creatorAvatarToNameGap: CGFloat = 8
    /// `Dimens.musicThumbnailWidth/Height`.
    static let musicCarouselSize: CGFloat = 220
    /// Flutter's `kToolbarHeight`.
    static let toolbarHeight: CGFloat = 56

    /// `HomeSimilarPlaylistRow` metrics.
    static let similarSeedAvatar: CGFloat = 48
    static let similarCoverSize: CGFloat = 120
    static let similarRailHeight: CGFloat = 164

    /// `HomeTopCompanyPlaylistUi` / `HomeSongRecommendationUi` grids.
    static let companyGridCover: CGFloat = 56
    static let companyGridGap: CGFloat = Dimens.spacing8
    static let companyGridMaxItems = 6
    static let recommendationGap: CGFloat = 10
    static let recommendationPadding: CGFloat = 8
    static let recommendationCover: CGFloat = 40
    static let recommendationCoverToTitleGap: CGFloat = 12

    /// `HomeTopWeeklyPlaylistCard`.
    static let weeklyCover: CGFloat = 96
    static let weeklyPadding: CGFloat = Dimens.spacing12

    /// `HomeListItemUi` (the vertical "Most Played Episodes" list).
    static let listInset: CGFloat = Dimens.screenPaddingAll * 2
    static let listCardPadding: CGFloat = Dimens.screenPaddingAll
    static let listAvatar: CGFloat = Dimens.userThumbnailSize
    static let listPlaySize: CGFloat = 26
    static let listFavouriteSize: CGFloat = 28

    /// Extra breathing room (24) so the last rail clears the ad strip + mini player.
    /// Bottom spacer under the feed: `Dimens.bottomSpacerHeight` plus
    /// `Ios26BottomSpacing(multiply: 3)` over a 56pt toolbar (the floating
    /// dock overlays the scroll view natively exactly as it does on Flutter).
    static let feedBottomSpacing: CGFloat = 24
    /// `Ios26BottomSpacing(multiply: 3)` on its own (sub-pages).
    static let pageBottomSpacing: CGFloat = 24

    /// `HomeCardTitle.lineHeight` (`AppTextStyles.homeCardTitleHeight`).
    static let cardTitleToken = TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.3)
    /// `Label` — 20pt w600.
    static let sectionTitleToken = TypographyToken(size: 20, weight: .semibold, lineHeightMultiple: 1)
}

/// Flutter colours (`lib/theme/colors.dart`) the home screens use verbatim.
enum HomeColors {
    static let background = Color.black
    /// `ColorTheme.fillColor` / `fillColor` (0xFF1D1D1D).
    static let fill = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1D / 255)
    /// `ColorTheme.darkFillColor` (0xFF282828).
    static let darkFill = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let white50 = Color.white.opacity(0.54)
    static let white24 = Color.white.opacity(0.24)
    static let white60 = Color.white.opacity(0.6)
    static let white70 = Color.white.opacity(0.7)
    /// `_Shimmer.base` / `.highlight` (`home_section_shimmer.dart`).
    static let shimmerBase = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x23 / 255)
    static let shimmerHighlight = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255)
    /// Episode / hero artwork scrim stops (`HomeEpisodeItemUi`).
    static var episodeScrim: Gradient {
        Gradient(stops: [
            Gradient.Stop(color: Color.black.opacity(0.05), location: 0.0),
            Gradient.Stop(color: Color.black.opacity(0.20), location: 0.45),
            Gradient.Stop(color: Color.black.opacity(0.75), location: 1.0),
        ])
    }
}

extension String {
    /// Dart's `String.capitalized` (velocity_x): upper-cases the first letter
    /// of each word and leaves the rest of the word alone — unlike
    /// Foundation's `capitalized`, which lower-cases the remainder ("AI" ->
    /// "Ai").
    var homeCapitalized: String {
        split(separator: " ", omittingEmptySubsequences: false)
            .map { word in String(word.prefix(1)).uppercased() + String(word.dropFirst()) }
            .joined(separator: " ")
    }

    var homeTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Playlist {
    /// The `AppRoute` that opens this playlist's own song page — album/season
    /// (`PlaylistSongPage`) and company playlist (`CompanyPlaylistSongsPage`)
    /// both land on `PlaylistDetailView`.
    var detailRoute: AppRoute {
        var creatorID: String?
        var creatorName: String?
        if case let .creator(id, name) = owner {
            creatorID = id
            creatorName = name
        }
        return .playlistDetail(
            playlistID: id,
            title: title,
            image: image,
            imageVariants: imageVariants,
            songsCount: songsCount,
            isCompanyOwned: owner == .company,
            creatorID: creatorID,
            creatorName: creatorName
        )
    }
}

/// `Formater.formatDurationText` / `formatNumber` (`lib/utils/formater.dart`).
enum HomeFormat {
    static func durationText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return String(localized: "0 min") }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return minutes > 0 ? String(localized: "\(hours)h \(minutes)m") : String(localized: "\(hours)h") }
        if minutes > 0 { return String(localized: "\(minutes) min") }
        return String(localized: "\(secs) sec")
    }

    /// `NumberFormat.compact()` — 1.2K / 3.4M, no decimals once >= 10.
    static func compactNumber(_ value: Int?) -> String {
        guard let value else { return "0" }
        let absolute = Double(abs(value))
        func format(_ number: Double, _ suffix: String) -> String {
            let rounded = number >= 10 ? number.rounded() : (number * 10).rounded() / 10
            let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
            return text + suffix
        }
        if absolute >= 1_000_000_000 { return format(Double(value) / 1_000_000_000, "B") }
        if absolute >= 1_000_000 { return format(Double(value) / 1_000_000, "M") }
        if absolute >= 1_000 { return format(Double(value) / 1_000, "K") }
        return String(value)
    }

    /// `l10n.mediaSongCount(count, formatNumber(count))` — `=1{1 Song} other{{formatted} Songs}`.
    static func songCountText(_ count: Int?) -> String {
        let count = count ?? 0
        return count == 1 ? String(localized: "1 Song") : String(localized: "\(compactNumber(count)) Songs")
    }

    /// `l10n.mediaPodcastCount(count, formatNumber(count))` — `=1{1 Podcast} other{{formatted} Podcasts}`.
    static func podcastCountText(_ count: Int?) -> String {
        let count = count ?? 0
        return count == 1 ? String(localized: "1 Podcast") : String(localized: "\(compactNumber(count)) Podcasts")
    }

    /// `l10n.creatorFollowerCount(count)` — `=1{1 Follower} other{{count} Followers}`.
    /// The plain count, not `compactNumber`: Dart doesn't abbreviate it — and
    /// interpolates it as `'$count'`, so no grouping separator (an `Int`
    /// argument would print "1,500").
    static func followerCountText(_ count: Int?) -> String {
        let count = count ?? 0
        return count == 1 ? String(localized: "1 Follower") : String(localized: "\(String(count)) Followers")
    }
}
