import SwiftUI

/// Ports `home_section_shimmer.dart`: every rail draws a skeleton with the
/// SAME silhouette (and height) as its loaded self, in the exact shimmer
/// colours (`0xFF232323` base, `0xFF3A3A3A` highlight, 1400ms period), so the
/// page does not jump as rails hydrate. One shimmer sweep per section, never
/// per card.
private struct HomeShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    private static let period: TimeInterval = 1.4

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: .clear, location: 0.0),
                            Gradient.Stop(color: .clear, location: 0.35),
                            Gradient.Stop(color: HomeColors.shimmerHighlight, location: 0.5),
                            Gradient.Stop(color: .clear, location: 0.65),
                            Gradient.Stop(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width)
                    .offset(x: phase * proxy.size.width)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .allowsHitTesting(false)
    }
}

extension View {
    func homeShimmer() -> some View { modifier(HomeShimmerModifier()) }
}

/// `_Box` — a filled rounded rectangle in the shimmer base colour.
struct HomeSkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .circular)
            .fill(HomeColors.shimmerBase)
            .frame(width: width, height: height)
    }
}

/// `_LineStyle` — which text style a placeholder line stands in for; the slot
/// is as tall as a real line of that style would be.
enum HomeSkeletonLineStyle {
    case labelSmall, bodySmall, bodyMedium, bodyLarge, titleSmall, titleMedium, titleLarge

    var fontSize: CGFloat {
        switch self {
        case .labelSmall: 11
        case .bodySmall: 12
        case .bodyMedium, .titleSmall: 14
        case .bodyLarge, .titleMedium: 16
        case .titleLarge: 20
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .labelSmall, .titleSmall, .titleMedium, .titleLarge: 1.4
        case .bodySmall, .bodyMedium, .bodyLarge: 1.5
        }
    }
}

struct HomeSkeletonLine: Identifiable {
    let id = UUID()
    let style: HomeSkeletonLineStyle
    let widthFactor: CGFloat
    var lineHeight: CGFloat?

    /// `_cardTitleLines` — two title lines at the card-title line height.
    static let cardTitle: [HomeSkeletonLine] = [
        HomeSkeletonLine(style: .titleSmall, widthFactor: 0.95, lineHeight: 1.3),
        HomeSkeletonLine(style: .titleSmall, widthFactor: 0.6, lineHeight: 1.3),
    ]
}

/// `_TextLine`.
struct HomeSkeletonTextLine: View {
    let line: HomeSkeletonLine
    var slotWidth: CGFloat?
    var centred = false

    var body: some View {
        let slotHeight = line.style.fontSize * (line.lineHeight ?? line.style.lineHeight)
        let barHeight = line.style.fontSize * 0.6
        HStack(spacing: 0) {
            if centred { Spacer(minLength: 0) }
            if let slotWidth {
                HomeSkeletonBox(width: slotWidth * line.widthFactor, height: barHeight, radius: 4)
            } else {
                GeometryReader { proxy in
                    HomeSkeletonBox(width: proxy.size.width * line.widthFactor, height: barHeight, radius: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            if centred || slotWidth == nil { Spacer(minLength: 0) }
        }
        .frame(height: slotHeight)
    }
}

/// `_CoverCard`.
struct HomeCoverCardSkeleton: View {
    let coverSize: CGFloat
    let coverRadius: CGFloat
    let gap: CGFloat
    var lines: [HomeSkeletonLine] = HomeSkeletonLine.cardTitle
    var centred = false

    var body: some View {
        VStack(alignment: centred ? .center : .leading, spacing: 0) {
            HomeSkeletonBox(width: coverSize, height: coverSize, radius: coverRadius)
            Color.clear.frame(height: gap)
            ForEach(lines) { line in
                HomeSkeletonTextLine(line: line, slotWidth: coverSize, centred: centred)
            }
        }
        .frame(width: coverSize)
    }
}

/// `_Rail` — five non-scrolling cards.
struct HomeRailSkeleton<Card: View>: View {
    let height: CGFloat
    let spacing: CGFloat
    private let card: Card

    init(height: CGFloat, spacing: CGFloat, @ViewBuilder card: () -> Card) {
        self.height = height
        self.spacing = spacing
        self.card = card()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                card.padding(.trailing, spacing)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

/// The skeleton `homeSectionShimmer(viewType:title:type:)` draws for a rail
/// that has not hydrated yet, header included.
struct HomeSectionSkeletonView: View {
    let viewType: String
    let title: String
    let type: String

    private var isEpisode: Bool { type == "episode" }

    var body: some View {
        switch viewType {
        case "trending":
            HomeSectionContainer(layout: .bleed, title: title) {
                carousel.homeShimmer()
            }
        case "creators":
            HomeSectionContainer(layout: .horizontalRow, title: title) {
                HomeRailSkeleton(height: Dimens.creatorRowHeight, spacing: Dimens.horizontalGapMedium) {
                    HomeCoverCardSkeleton(
                        coverSize: HomeMetrics.creatorAvatarSize,
                        coverRadius: HomeMetrics.creatorAvatarSize / 2,
                        gap: HomeMetrics.creatorAvatarToNameGap,
                        lines: [HomeSkeletonLine(style: .bodySmall, widthFactor: 0.85)],
                        centred: true
                    )
                }
                .homeShimmer()
            }
        case "podcasts", "playlists", "recentMixed":
            HomeSectionContainer(layout: .horizontalRow, title: title) {
                coverRail(radius: Dimens.cornerRadiusSmall)
            }
        case "aiPlaylist":
            HomeSectionContainer(layout: .horizontalRow, title: title) {
                coverRail(radius: Dimens.cornerRadius)
            }
        case "singleCompanyPlaylist":
            HomeSectionContainer(layout: .fullWidth, title: title) {
                topWeekly.homeShimmer()
            }
        case "companyPlaylists":
            HomeSectionContainer(layout: .fullWidth, title: title) {
                companyGrid.homeShimmer()
            }
        case "similarPlaylist":
            HomeSectionContainer(layout: .bleed) {
                similar.homeShimmer()
            }
        case "listSongs":
            listSongs
                .padding(.horizontal, HomeMetrics.listInset)
                .homeShimmer()
        case "recommended":
            if isEpisode {
                songRail
            } else {
                HomeSectionContainer(layout: .fullWidth, title: title) {
                    recommendationGrid.homeShimmer()
                }
            }
        default:
            songRail
        }
    }

    // MARK: Pieces

    private func coverRail(radius: CGFloat) -> some View {
        HomeRailSkeleton(height: HomeMetrics.railHeight, spacing: HomeMetrics.cardSpacing) {
            HomeCoverCardSkeleton(
                coverSize: HomeMetrics.coverSize,
                coverRadius: radius,
                gap: HomeMetrics.coverToTitleGap
            )
        }
        .homeShimmer()
    }

    @ViewBuilder
    private var songRail: some View {
        HomeSectionContainer(layout: .horizontalRow, title: title) {
            if isEpisode {
                HomeRailSkeleton(height: HomeMetrics.railHeight, spacing: HomeMetrics.cardSpacing) {
                    HomeSkeletonBox(
                        width: HomeMetrics.episodeCardWidth,
                        height: HomeMetrics.railHeight,
                        radius: Dimens.cornerRadiusSmall
                    )
                }
                .homeShimmer()
            } else {
                coverRail(radius: Dimens.cornerRadiusSmall)
            }
        }
    }

    private var carousel: some View {
        let cardWidth = isEpisode ? HomeMetrics.episodeCardHeight * 16 / 9 : HomeMetrics.musicCarouselSize
        let railHeight = (isEpisode ? HomeMetrics.episodeCardHeight : HomeMetrics.musicCarouselSize) + (isEpisode ? 30 : 10)
        // Clamped to the rail, as in `HomeTrendingCarouselView.cardHeight`.
        let cardHeight = min((isEpisode ? HomeMetrics.episodeCardHeight : HomeMetrics.musicCarouselSize) + 30, railHeight)
        let sideScale = max(HomeTrendingCarouselView.minCardScale, 1 - HomeTrendingCarouselView.scaleStep)
        let offset = cardWidth / 2 + 10 + (cardWidth * sideScale) / 2
        return ZStack {
            HomeSkeletonBox(width: cardWidth, height: cardHeight, radius: Dimens.cornerRadius)
                .scaleEffect(sideScale)
                .offset(x: -offset)
            HomeSkeletonBox(width: cardWidth, height: cardHeight, radius: Dimens.cornerRadius)
                .scaleEffect(sideScale)
                .offset(x: offset)
            HomeSkeletonBox(width: cardWidth, height: cardHeight, radius: Dimens.cornerRadius)
        }
        .frame(maxWidth: .infinity)
        .frame(height: railHeight)
        .clipped()
    }

    private var companyGrid: some View {
        let rows = HomeMetrics.companyGridMaxItems / 2
        return VStack(spacing: HomeMetrics.companyGridGap) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: HomeMetrics.companyGridGap) {
                    companyGridCard
                    companyGridCard
                }
            }
        }
    }

    private var companyGridCard: some View {
        HStack(spacing: Dimens.spacing8) {
            HomeSkeletonBox(
                width: HomeMetrics.companyGridCover,
                height: HomeMetrics.companyGridCover,
                radius: Dimens.cornerRadiusSmall
            )
            VStack(alignment: .leading, spacing: 0) {
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleSmall, widthFactor: 1.0, lineHeight: 1.25))
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleSmall, widthFactor: 0.6, lineHeight: 1.25))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Dimens.spacing8)
        .frame(maxWidth: .infinity)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
    }

    private var similar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Dimens.spacing12) {
                HomeSkeletonBox(
                    width: HomeMetrics.similarSeedAvatar,
                    height: HomeMetrics.similarSeedAvatar,
                    radius: HomeMetrics.similarSeedAvatar / 2
                )
                VStack(alignment: .leading, spacing: 0) {
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleSmall, widthFactor: 0.4))
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleLarge, widthFactor: 0.65))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Dimens.sectionPaddingH)
            Color.clear.frame(height: HomeMetrics.cardSpacing)
            HomeRailSkeleton(height: HomeMetrics.similarRailHeight, spacing: HomeMetrics.cardSpacing) {
                HomeCoverCardSkeleton(
                    coverSize: HomeMetrics.similarCoverSize,
                    coverRadius: Dimens.cornerRadius,
                    gap: HomeMetrics.coverToTitleGap
                )
            }
            .padding(.leading, Dimens.sectionPaddingH)
        }
    }

    private var topWeekly: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Dimens.spacing12) {
                HomeSkeletonBox(
                    width: HomeMetrics.weeklyCover,
                    height: HomeMetrics.weeklyCover,
                    radius: Dimens.cornerRadiusSmall
                )
                VStack(alignment: .leading, spacing: 0) {
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleLarge, widthFactor: 0.9))
                    Color.clear.frame(height: 2)
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleMedium, widthFactor: 0.5))
                }
                .frame(maxWidth: .infinity)
            }
            Color.clear.frame(height: Dimens.spacing12)
            ForEach(0..<3, id: \.self) { _ in
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodyLarge, widthFactor: 1.0))
            }
            Color.clear.frame(height: Dimens.spacing12)
            HStack {
                Spacer(minLength: 0)
                HomeSkeletonBox(width: 48, height: 48, radius: 24)
            }
        }
        .padding(HomeMetrics.weeklyPadding)
        .frame(maxWidth: .infinity)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
    }

    private var recommendationGrid: some View {
        VStack(spacing: HomeMetrics.recommendationGap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: HomeMetrics.recommendationGap) {
                    recommendationCard
                    recommendationCard
                }
            }
        }
    }

    private var recommendationCard: some View {
        HStack(spacing: HomeMetrics.recommendationCoverToTitleGap) {
            HomeSkeletonBox(
                width: HomeMetrics.recommendationCover,
                height: HomeMetrics.recommendationCover,
                radius: Dimens.cornerRadiusSmall
            )
            VStack(alignment: .leading, spacing: 0) {
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodyMedium, widthFactor: 1.0))
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodyMedium, widthFactor: 0.55))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(HomeMetrics.recommendationPadding)
        .frame(maxWidth: .infinity)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .circular))
    }

    private var listSongs: some View {
        VStack(spacing: 0) {
            listSongCard
            listSongCard
        }
    }

    private var listSongCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().fill(HomeColors.shimmerBase))
                .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
            Color.clear.frame(height: Dimens.verticalSpacing)
            HStack(spacing: 0) {
                HomeSkeletonBox(
                    width: HomeMetrics.listAvatar,
                    height: HomeMetrics.listAvatar,
                    radius: Dimens.cornerRadiusSmall
                )
                Color.clear.frame(width: Dimens.leadingSpacing)
                VStack(alignment: .leading, spacing: 0) {
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .titleSmall, widthFactor: 0.85))
                    Color.clear.frame(height: 4)
                    HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodySmall, widthFactor: 0.6))
                }
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: Dimens.spacing8)
                HomeSkeletonBox(
                    width: HomeMetrics.listFavouriteSize,
                    height: HomeMetrics.listFavouriteSize,
                    radius: HomeMetrics.listFavouriteSize / 2
                )
                .padding(Dimens.paddingSmall)
                Color.clear.frame(width: Dimens.spacing4)
                HomeSkeletonBox(
                    width: HomeMetrics.listPlaySize,
                    height: HomeMetrics.listPlaySize,
                    radius: HomeMetrics.listPlaySize / 2
                )
            }
            .padding(.horizontal, HomeMetrics.listCardPadding)
            Color.clear.frame(height: Dimens.verticalSpacing + 4)
            VStack(alignment: .leading, spacing: 0) {
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodySmall, widthFactor: 1.0, lineHeight: 1.4))
                HomeSkeletonTextLine(line: HomeSkeletonLine(style: .bodySmall, widthFactor: 0.7, lineHeight: 1.4))
            }
            .padding(.horizontal, HomeMetrics.listCardPadding)
        }
        .padding(HomeMetrics.listCardPadding)
        .frame(maxWidth: .infinity)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .padding(.bottom, HomeMetrics.listInset)
    }
}
