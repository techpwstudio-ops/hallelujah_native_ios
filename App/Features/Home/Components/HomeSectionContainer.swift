import SwiftUI

/// `HomeSectionLayout` (`lib/views/home/sections/home_section.dart`).
enum HomeSectionLayoutKind {
    /// Header padded both sides; body indented from the left only so cards
    /// bleed past the right screen edge.
    case horizontalRow
    /// Full-width content padded on both sides.
    case fullWidth
    /// Body paints edge-to-edge and owns its own horizontal padding.
    case bleed
}

/// `SectionHeader` — a 20pt w600 title (`Label`) and an optional trailing
/// "See All" `TextButton` (titleSmall, white54, 8pt horizontal padding).
struct HomeSectionHeaderView: View {
    let title: String
    var onSeeAll: (() -> Void)?

    /// `SectionHeader.trailingInset`.
    static let trailingInset: CGFloat = Dimens.spacing8

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .typography(HomeMetrics.sectionTitleToken)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    Text("See All")
                        .typography(Typography.titleSmall)
                        .foregroundStyle(HomeColors.white50)
                        .padding(.horizontal, Self.trailingInset)
                        .frame(minWidth: 64, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// `HomeSection` — header, fixed header-to-body gap (`sectionHeaderGap` 12),
/// layout-aware body padding and the uniform gap below every section
/// (`sectionGap` 8).
struct HomeSectionContainer<Content: View>: View {
    let layout: HomeSectionLayoutKind
    var title: String?
    var onSeeAll: (() -> Void)?
    private let content: Content

    init(
        layout: HomeSectionLayoutKind,
        title: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.layout = layout
        self.title = title
        self.onSeeAll = onSeeAll
        self.content = content()
    }

    private var bodyLeading: CGFloat {
        switch layout {
        case .horizontalRow, .fullWidth: Dimens.sectionPaddingH
        case .bleed: 0
        }
    }

    private var bodyTrailing: CGFloat {
        switch layout {
        case .fullWidth: Dimens.sectionPaddingH
        case .horizontalRow, .bleed: 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HomeSectionHeaderView(title: title, onSeeAll: onSeeAll)
                    .padding(.leading, Dimens.sectionPaddingH)
                    .padding(
                        .trailing,
                        onSeeAll == nil ? Dimens.sectionPaddingH : Dimens.sectionPaddingH - HomeSectionHeaderView.trailingInset
                    )
                Color.clear.frame(height: Dimens.sectionHeaderGap)
            }
            content
                .padding(.leading, bodyLeading)
                .padding(.trailing, bodyTrailing)
        }
        .padding(.bottom, Dimens.sectionGap)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `HomeCardTitle` — the title under a square card: capitalised, trimmed,
/// two lines before the ellipsis, 14pt w600 at 1.3 line height.
struct HomeCardTitleView: View {
    let title: String

    var body: some View {
        Text(title.homeCapitalized.homeTrimmed)
            .typography(HomeMetrics.cardTitleToken)
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A horizontal rail of fixed height (`SizedBox(height:) + ListView`).
struct HomeRailScroll<Content: View>: View {
    var height: CGFloat = HomeMetrics.railHeight
    private let content: Content

    init(height: CGFloat = HomeMetrics.railHeight, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                content
            }
        }
        .frame(height: height)
    }
}

/// Square (or arbitrary) artwork card chrome shared by the song, playlist,
/// creator-as-podcast and recent rails: artwork, 6pt gap, two-line title,
/// 16pt trailing gap.
struct HomeSquareCard<Overlay: View>: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let title: String
    private let overlay: Overlay

    init(
        url: URL?,
        size: CGFloat = HomeMetrics.coverSize,
        cornerRadius: CGFloat = Dimens.cornerRadiusSmall,
        title: String,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self.title = title
        self.overlay = overlay()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(url: url, width: size, height: size, cornerRadius: cornerRadius)
                .overlay(alignment: .bottom) { overlay }
            Color.clear.frame(height: HomeMetrics.coverToTitleGap)
            HomeCardTitleView(title: title)
        }
        .frame(width: size, alignment: .topLeading)
        .padding(.trailing, HomeMetrics.cardSpacing)
    }
}

extension HomeSquareCard where Overlay == EmptyView {
    init(
        url: URL?,
        size: CGFloat = HomeMetrics.coverSize,
        cornerRadius: CGFloat = Dimens.cornerRadiusSmall,
        title: String
    ) {
        self.init(url: url, size: size, cornerRadius: cornerRadius, title: title) { EmptyView() }
    }
}
