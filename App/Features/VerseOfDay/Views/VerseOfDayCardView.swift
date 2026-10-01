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

    var body: some View {
        Group {
            if viewModel.isVisible, let verse = viewModel.verse {
                VerseOfDayCardContentView(verse: verse, viewModel: viewModel)
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}

/// Split from `VerseOfDayCardView` so every sheet/gesture closure below
/// captures a plain, already-unwrapped `verse: VerseOfDay` — no repeated
/// `viewModel.verse!`/optional-binding noise at each call site.
private struct VerseOfDayCardContentView: View {
    let verse: VerseOfDay
    let viewModel: VerseOfDayCardViewModel

    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()
    @State private var showOptionsSheet = false
    @State private var showAskEmetSheet = false
    @State private var showCommentsSheet = false
    @State private var showHistorySheet = false

    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var backgroundURL: URL? {
        ArtworkURLResolver().resolve(path: verse.backgroundImage, variant: .lg, allowedVariants: nil)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VerseOfDayBackgroundImageView(url: backgroundURL)
                .opacity(0.8)
            VerseOfDayScrimOverlay()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("VERSE OF THE DAY")
                    .typography(Typography.labelSmall)
                    .foregroundStyle(theme.color(.textInverse).opacity(0.8))

                Button(action: navigateToReader) {
                    Text(verse.verseText ?? "")
                        .typography(Typography.titleMedium)
                        .foregroundStyle(theme.color(.textInverse))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(verse.bookNumber == nil || verse.chapterNumber == nil)

                if let reference = verse.reference {
                    Text(reference)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textInverse).opacity(0.8))
                }

                VerseOfDayActionBar(
                    verse: verse,
                    isTogglingLike: viewModel.isTogglingLike,
                    shareURL: viewModel.shareURL,
                    onLikeTap: { Task { await viewModel.toggleLike() } },
                    onCommentTap: { showCommentsSheet = true },
                    onHistoryTap: { showHistorySheet = true }
                )
            }
            .padding(Spacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .onLongPressGesture {
            showOptionsSheet = true
        }
        .appSheet(isPresented: $showOptionsSheet) {
            VerseOfDayOptionsSheet(
                verse: verse,
                onHide: { viewModel.hideForToday() },
                onAskEmet: { showAskEmetSheet = true }
            )
        }
        .sheet(isPresented: $showAskEmetSheet) {
            AIVerseInsightDialogView(target: .fromVerseOfDay(verse))
        }
        .appSheet(isPresented: $showCommentsSheet) {
            VerseOfDayCommentsSheet(verseOfDayId: verse.id)
        }
        .appSheet(isPresented: $showHistorySheet) {
            VerseOfDayHistorySheet()
        }
    }

    /// `DashboardNavigateTo(4)` + the reader's own book/chapter navigation
    /// (`_VerseOfDaySection`'s verse tap) — switches to the Read tab and
    /// hands it a pending target the same way a push notification/deep link
    /// does (`ReaderNavigationStore`, shared via DI with both of those).
    private func navigateToReader() {
        guard let bookNumber = verse.bookNumber, let chapterNumber = verse.chapterNumber else { return }
        coordinator.selectedTab = .read
        navigationStore.pendingTarget = ReaderNavigationStore.Target(bookNumber: bookNumber, chapterNumber: chapterNumber)
    }
}

/// The like/comment/share/history row. Ports `VerseOfDayActionBar`
/// (`verse_action_bar.dart`)'s four slots. Plain integer counts, no
/// `Formater.formatNumber` abbreviation — same "no native equivalent exists"
/// precedent `CreatorPlaylistRow`'s own doc comment already established —
/// with `.contentTransition(.numericText())` (iOS 16+, well under this
/// project's iOS 17 deployment target) standing in for Dart's own
/// `AnimatedCount`/`AnimatedSwitcher` widget rather than hand-porting it.
private struct VerseOfDayActionBar: View {
    let verse: VerseOfDay
    let isTogglingLike: Bool
    let shareURL: URL?
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onHistoryTap: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Button(action: onLikeTap) {
                counted(
                    icon: verse.isLiked ? .favoriteFilled : .favorite,
                    count: verse.likes,
                    tint: verse.isLiked ? theme.color(.statusError) : theme.color(.textInverse)
                )
            }
            .buttonStyle(.plain)
            .disabled(isTogglingLike)

            Button(action: onCommentTap) {
                counted(icon: .comment, count: verse.comments, tint: theme.color(.textInverse))
            }
            .buttonStyle(.plain)

            shareButton

            Button(action: onHistoryTap) {
                theme.icon(.history)
                    .foregroundStyle(theme.color(.textInverse))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .animation(MotionCurve.fast, value: verse.likes)
        .animation(MotionCurve.fast, value: verse.comments)
    }

    private func counted(icon: IconToken, count: Int, tint: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            theme.icon(icon)
            Text("\(count)")
                .typography(Typography.labelMedium)
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint)
    }

    /// `shareURL` is only `nil` until `VerseOfDayCardViewModel.refresh()`
    /// resolves it — `ShareLink(item:)` needs its item ready synchronously
    /// at tap time (see that view model's own doc comment), so this renders
    /// the same glyph+count either way and only becomes a real `ShareLink`
    /// once the URL is in hand, rather than the row reflowing when it
    /// arrives.
    @ViewBuilder
    private var shareButton: some View {
        let label = counted(icon: .share, count: verse.shares, tint: theme.color(.textInverse))
        if let shareURL {
            ShareLink(item: shareURL) { label }
        } else {
            label.opacity(0.5)
        }
    }
}

/// The dark top/middle/bottom gradient every verse-of-day background image
/// sits under, so on-image text stays legible regardless of the photo
/// beneath it. Mirrors `verse_bg_widget.dart`'s `ColorTheme.dark.withOpacity(
/// 0.5/0.1/0.5)` top-to-bottom gradient, built from the `overlayScrim` color
/// set (`Assets.xcassets` — a token purpose-built for exactly this, with no
/// other call site yet) rather than a raw `Color.black.opacity(...)` literal.
/// Not `private`: `VerseOfDayHistorySheet`'s own past-verse rows reuse it.
struct VerseOfDayScrimOverlay: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: theme.color(.overlayScrim).opacity(0.5), location: 0),
                .init(color: theme.color(.overlayScrim).opacity(0.1), location: 0.5),
                .init(color: theme.color(.overlayScrim).opacity(0.5), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The verse-of-day card's background photo. A `GeometryReader`-sized sister
/// to `ArtworkView` (see that file's own doc comment on why raw `AsyncImage`
/// is avoided here too — same `ArtworkImageCache` downsampling call), built
/// as its own type instead of reusing `ArtworkView` directly for one reason:
/// `ArtworkView` takes fixed `width`/`height`, but this card has no fixed
/// aspect ratio (`VerseOfDayCardView`'s own doc comment) — its box is
/// whatever height the foreground content naturally produces, known only at
/// layout time, which is exactly what `GeometryReader` provides and a fixed
/// pair of stored properties can't. Not `private`: `VerseOfDayHistorySheet`'s
/// own past-verse rows reuse it too.
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
                    theme.color(.surfaceSecondary)
                }
            }
            .task(id: LoadKey(url: url, size: proxy.size)) {
                await load(maxPixelSize: max(proxy.size.width, proxy.size.height) * displayScale)
            }
        }
    }

    @Environment(\.appTheme) private var theme

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
