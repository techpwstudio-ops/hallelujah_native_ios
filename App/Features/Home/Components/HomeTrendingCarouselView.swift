import SwiftUI

/// `HomeSongTrendingUi` / `HomeEpisodeTrendingUi` — a centred stack of scaled
/// cards (rank 1 in the middle, alternating left/right) driven by a horizontal
/// drag. Neighbouring cards sit `cardSpread` apart and shrink by `scaleStep`
/// per step (floored at `minCardScale`); only the front card shows its title.
/// Tapping anywhere plays the front card's song, queue in carousel order, as
/// `PlayerType.home` with the section uiId.
struct HomeTrendingCarouselView: View {
    let songs: [Song]
    let uiId: String
    var isEpisode = false

    static let cardSpread: CGFloat = 120
    static let scaleStep: CGFloat = 0.15
    static let minCardScale: CGFloat = 0.75

    @Environment(AppNavigationCoordinator.self) private var coordinator

    @State private var page: Double
    @State private var dragStartPage: Double?
    private let ordered: [Song]

    init(songs: [Song], uiId: String, isEpisode: Bool = false) {
        self.songs = songs
        self.uiId = uiId
        self.isEpisode = isEpisode
        let reordered = Self.reorderForCenter(songs)
        ordered = reordered
        _page = State(initialValue: Double(reordered.count / 2))
    }

    /// `[r1, r2, …, rN]` -> `[… r6, r4, r2, r1, r3, r5, r7 …]`.
    private static func reorderForCenter(_ sorted: [Song]) -> [Song] {
        let count = sorted.count
        guard count > 0 else { return sorted }
        var result: [Song?] = Array(repeating: nil, count: count)
        let center = count / 2
        result[center] = sorted[0]
        if count > 1 {
            for index in 1..<count {
                let side = (index + 1) / 2
                let position = index % 2 == 1 ? center - side : center + side
                if position >= 0 && position < count { result[position] = sorted[index] }
            }
        }
        return result.compactMap { $0 }
    }

    private var cardWidth: CGFloat { isEpisode ? HomeMetrics.episodeCardWidth : HomeMetrics.musicCarouselSize }
    private var imageHeight: CGFloat { isEpisode ? HomeMetrics.episodeCardHeight : HomeMetrics.musicCarouselSize }
    private var cardHeight: CGFloat { imageHeight + 30 }
    private var railHeight: CGFloat { imageHeight + (isEpisode ? 30 : 10) }

    var body: some View {
        GeometryReader { proxy in
            let viewport = max(proxy.size.width, 1)
            ZStack {
                ForEach(visibleOffsets, id: \.self) { offset in
                    cardLayer(offset: offset)
                }
            }
            .frame(width: proxy.size.width, height: railHeight)
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag(viewport: viewport))
            .onTapGesture(perform: playFront)
        }
        .frame(height: railHeight)
    }

    private var visibleOffsets: [Int] { [-2, -1, 0, 1, 2] }

    private func cardLayer(offset: Int) -> some View {
        let count = ordered.count
        let centerIndex = Int(page.rounded())
        let virtualIndex = centerIndex + offset
        let realIndex = ((virtualIndex % count) + count) % count
        let difference = Double(virtualIndex) - page
        let absDiff = abs(difference)
        let scale = max(Double(Self.minCardScale), 1 - absDiff * Double(Self.scaleStep))
        return card(song: ordered[realIndex], isFront: absDiff < 0.5)
            .scaleEffect(CGFloat(scale))
            .offset(x: CGFloat(difference) * Self.cardSpread)
            .zIndex(-absDiff)
    }

    private func card(song: Song, isFront: Bool) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ArtworkView(
                    url: HomeArt.url(song.image, song.imageVariants, .md),
                    width: cardWidth,
                    height: imageHeight,
                    cornerRadius: Dimens.cornerRadius
                )
                Spacer(minLength: 0)
            }
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            if isFront {
                Text(song.title ?? "")
                    .typography(Typography.titleMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Dimens.spacing8)
                    .padding(.bottom, 36)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .circular))
    }

    // MARK: Interaction

    private func drag(viewport: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStartPage == nil { dragStartPage = page }
                page = (dragStartPage ?? page) - Double(value.translation.width / viewport)
            }
            .onEnded { value in
                let start = dragStartPage ?? page
                dragStartPage = nil
                let projected = start - Double(value.predictedEndTranslation.width / viewport)
                let target = (projected.rounded())
                withAnimation(.easeOut(duration: 0.3)) { page = target }
            }
    }

    private func playFront() {
        guard !ordered.isEmpty else { return }
        let count = ordered.count
        let index = ((Int(page.rounded()) % count) + count) % count
        HomePlayback.shared.play(
            song: ordered[index],
            in: ordered,
            source: HomePlayback.homeAttribution(uiId: uiId),
            coordinator: coordinator
        )
    }
}
