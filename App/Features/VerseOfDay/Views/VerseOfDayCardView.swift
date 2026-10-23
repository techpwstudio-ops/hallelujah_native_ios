import SwiftUI
import UIKit

/// T56 — the Home rail's verse-of-day special case
/// (`HomeSectionRailView`'s `viewType == "verseOfDay"` branch). Ports
/// `VerseOfDayUi`/`_VerseOfDaySection` (`lib/widgets/verse_of_day/
/// verse_of_day_ui.dart`, `lib/views/home/sections/home_section_builder.dart`):
/// a full-width background-image card sized to its own content (no fixed
/// aspect ratio — confirmed by a direct read, Dart's `Stack` sizes to its
/// `Column` child, not the other way around), tap-to-read the verse,
/// long-press for the options sheet, and a like/comment/share/history action
/// bar. Entirely local-state-driven: never mounts unless `VerseOfDayCardViewModel.
/// refresh()` finds something already cached (see that type's own doc
/// comment on why there's no network fetch here).
struct VerseOfDayCardView: View {
    @State private var viewModel = VerseOfDayCardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A real (zero-height when hidden) container, not a `Group`: with
        // nothing inside, a `Group` is an empty view and its modifiers below
        // can be dropped, so a hidden card stopped listening for "unhide"
        // and only a pull-to-refresh (which rebuilt it) brought it back.
        VStack(spacing: 0) {
            if viewModel.isVisible, let verse = viewModel.verse {
                VerseOfDayCardContentView(verse: verse, viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            await viewModel.refresh()
        }
        // Back on Home (another tab, or popped back from Settings).
        .onAppear {
            Task { @MainActor in await viewModel.refresh() }
        }
        // The Home feed, a delivered push or a realtime update just stored a
        // newer verse / count (Flutter's `VerseOfDayHistoryBloc` state stream).
        .onReceive(NotificationCenter.default.publisher(for: .verseOfDayDidChange)) { _ in
            Task { @MainActor in await viewModel.refresh() }
        }
        // "Hide for today" ends at midnight: re-check when the app comes
        // back rather than staying hidden until the next relaunch.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in await viewModel.refresh() }
        }
    }
}

/// `VerseOfDayUi` (`lib/widgets/verse_of_day/verse_of_day_ui.dart`): the
/// artwork at 80% opacity under a black 50/10/50% gradient (12pt radius),
/// 16pt padding around: the "VERSE OF THE DAY" label, the quoted verse (tap
/// jumps the reader to it), the right-aligned "Book . ch . v" line, then the
/// like / comments / share / history action bar. Long-press opens the
/// options sheet.
private struct VerseOfDayCardContentView: View {
    let verse: VerseOfDay
    let viewModel: VerseOfDayCardViewModel

    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()
    @State private var showOptionsSheet = false
    @State private var showAskEmetSheet = false
    @State private var showCommentsSheet = false
    @State private var showHistorySheet = false
    @State private var pendingAfterOptions: (() -> Void)?

    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var backgroundURL: URL? {
        ArtworkURLResolver().resolve(path: verse.backgroundImage, variant: .lg, allowedVariants: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VerseOfDayContentBlock(
                verse: verse,
                onVerseTap: navigateToReader
            )
            Spacer().frame(height: 6)
            VerseOfDayMetaText(verse: verse)
            Spacer().frame(height: 14)
            VerseOfDayActionBar(
                verse: verse,
                shareURL: viewModel.shareURL,
                onLikeTap: { Task { await viewModel.toggleLike() } },
                onCommentTap: { showCommentsSheet = true },
                onHistoryTap: { showHistorySheet = true }
            )
        }
        .padding(Dimens.paddingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                VerseOfDayBackgroundImageView(url: backgroundURL)
                    .opacity(0.8)
                VerseOfDayScrimOverlay()
            }
            .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous))
        )
        .contentShape(Rectangle())
        // Simultaneous, so a long-press anywhere on the card opens the
        // options without swallowing the verse tap, the action buttons or
        // the feed's scrolling.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in showOptionsSheet = true }
        )
        .readSheet(
            isPresented: $showOptionsSheet,
            onDismiss: {
                guard let action = pendingAfterOptions else { return }
                pendingAfterOptions = nil
                action()
            },
            detents: [.height(200)]
        ) {
            VerseOfDayOptionsSheet(
                verse: verse,
                // After the sheet is gone: hiding first removed the card the
                // sheet was presented from, yanking the sheet away mid-tap.
                onHide: { pendingAfterOptions = { withAnimation { viewModel.hideForToday() } } },
                onAskEmet: { pendingAfterOptions = { showAskEmetSheet = true } },
                onClose: { showOptionsSheet = false }
            )
        }
        .fullScreenCover(isPresented: $showAskEmetSheet) {
            AIVerseInsightDialogView(target: .fromVerseOfDay(verse))
        }
        .readSheet(isPresented: $showCommentsSheet, detents: [.fraction(0.65), .fraction(0.95)]) {
            VerseOfDayCommentsSheet(verseOfDayId: verse.id, showsVerseOfDay: false)
        }
        .readSheet(isPresented: $showHistorySheet, detents: [.fraction(0.65), .fraction(0.95)]) {
            VerseOfDayHistorySheet()
        }
    }

    private func navigateToReader() {
        guard let bookNumber = verse.bookNumber, let chapterNumber = verse.chapterNumber else { return }
        coordinator.selectedTab = .read
        navigationStore.pendingTarget = ReaderNavigationStore.Target(
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            verseNumber: verse.verseNumber
        )
    }
}

/// `VerseOfDayContentUi`: "VERSE OF THE DAY" (labelSmall), a 12pt gap, then
/// the verse between bold-italic quotation marks (text bodyLarge w700).
struct VerseOfDayContentBlock: View {
    let verse: VerseOfDay
    /// A plain tap gesture, not a `Button`: a button swallowed the touch so
    /// the card's long-press (its options sheet) never fired over the verse.
    let onVerseTap: () -> Void

    private var comma: Text {
        Text("\"")
            .font(.custom(Typography.fontFamily, size: 24, relativeTo: .body).weight(.bold).italic())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Verse of the day".uppercased())
                .typography(Typography.labelSmall)
                .foregroundStyle(ReadPalette.white)
            Spacer().frame(height: Dimens.verticalSpacing)
            (comma
                + Text(" \(verse.verseText ?? "") ")
                    .font(.custom(Typography.fontFamily, size: 16, relativeTo: .body).weight(.bold))
                + comma)
                .lineSpacing(16 * 0.5)
                .foregroundStyle(ReadPalette.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onVerseTap)
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// `VerseOfDayMetaUi`: "Book . chapter . verse", bodySmall w700, right aligned.
struct VerseOfDayMetaText: View {
    let verse: VerseOfDay

    private var text: String {
        let chapter = verse.chapterNumber.map(String.init) ?? ""
        let number = verse.verseNumber.map(String.init) ?? ""
        return String(localized: "\(verse.bookName ?? "") . \(chapter) . \(number)")
    }

    var body: some View {
        Text(text)
            .readText(Typography.bodySmall, weight: .bold)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// `AnimatedCount`: collapses to nothing at zero, compact number ("1.2K"),
/// slides/fades when it changes.
struct VerseOfDayAnimatedCount: View {
    let count: Int
    var color: Color = ReadPalette.white

    private var formatted: String {
        count.formatted(.number.notation(.compactName))
    }

    private var width: CGFloat {
        if count <= 0 { return 0 }
        if formatted.count <= 2 { return 24 }
        if formatted.count <= 4 { return 32 }
        return 40
    }

    var body: some View {
        Text(formatted)
            .readText(Typography.bodySmall, weight: .regular, color: color)
            .contentTransition(.numericText())
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .opacity(count > 0 ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: count)
    }
}

/// `FavoriteIcon`: outline heart, or a red heart in a thin `redAccent` rim.
struct VerseOfDayHeartIcon: View {
    let isLiked: Bool
    var isLoading = false
    var size: CGFloat = 22
    var color: Color = ReadPalette.white

    var body: some View {
        // Flutter: `AnimatedSwitcher(200ms, ScaleTransition)` keyed on the liked flag.
        ZStack { icon.id(isLiked).transition(.scale) }
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.2), value: isLiked)
    }

    private var icon: some View {
        Group {
            if isLoading {
                ReadSpinner(size: size - 4, color: ReadPalette.white)
                    .frame(width: size, height: size)
            } else if isLiked {
                ZStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size))
                        .foregroundStyle(Color(readRGB: 0xFF5252))
                    Image(systemName: "heart.fill")
                        .font(.system(size: size - 1))
                        .foregroundStyle(Color(readRGB: 0xBA0319))
                }
                .frame(width: size, height: size)
            } else {
                Image(systemName: "heart")
                    .font(.system(size: size))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// `VerseOfDayActionBar`: four equal slots, icon left-aligned in each (22pt,
/// 8pt vertical tap padding), a 6pt gap to the count where there is one.
private struct VerseOfDayActionBar: View {
    let verse: VerseOfDay
    let shareURL: URL?
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onHistoryTap: () -> Void

    private static let iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            slot(onTap: onLikeTap) {
                HStack(spacing: 6) {
                    VerseOfDayHeartIcon(isLiked: verse.isLiked, size: Self.iconSize)
                    if verse.likes > 0 {
                        VerseOfDayAnimatedCount(count: verse.likes)
                    }
                }
            }
            slot(onTap: onCommentTap) {
                HStack(spacing: 6) {
                    Image(systemName: IconToken.comment.systemName)
                        .font(.system(size: Self.iconSize))
                        .foregroundStyle(ReadPalette.white)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    if verse.comments > 0 {
                        VerseOfDayAnimatedCount(count: verse.comments)
                    }
                }
            }
            shareSlot
            slot(onTap: onHistoryTap) {
                Image(systemName: IconToken.history.systemName)
                    .font(.system(size: Self.iconSize))
                    .foregroundStyle(ReadPalette.white)
                    .frame(width: Self.iconSize, height: Self.iconSize)
            }
        }
    }

    private func slot<Content: View>(onTap: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: onTap) {
            content()
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var shareSlot: some View {
        let icon = Image(systemName: IconToken.share.systemName)
            .font(.system(size: Self.iconSize))
            .foregroundStyle(ReadPalette.white)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        if let shareURL {
            ShareLink(item: shareURL) { icon }
                .buttonStyle(.plain)
        } else {
            icon.opacity(0.5)
        }
    }
}

/// The artwork scrim: black at 50% / 10% / 50%, top to bottom (12pt radius).
struct VerseOfDayScrimOverlay: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.5), location: 0),
                .init(color: Color.black.opacity(0.1), location: 0.5),
                .init(color: Color.black.opacity(0.5), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous))
    }
}

struct VerseOfDayBackgroundImageView: View {
    let url: URL?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct LoadKey: Equatable {
        let url: URL?
        let size: CGSize
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    ReadPalette.fill
                }
            }
            .task(id: LoadKey(url: url, size: proxy.size)) {
                await load(maxPixelSize: max(proxy.size.width, proxy.size.height) * displayScale)
            }
        }
    }


    private func load(maxPixelSize: CGFloat) async {
        guard let url, maxPixelSize.isFinite, maxPixelSize > 0 else {
            image = nil
            return
        }
        let requestedURL = url
        let decoded = await ArtworkImageCache.shared.image(for: requestedURL, maxPixelSize: maxPixelSize)
        guard self.url == requestedURL else { return }
        image = decoded
    }
}
