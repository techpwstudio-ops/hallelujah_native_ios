import SwiftUI

/// T56 — ports `showVerseOfDayHistory`'s sheet body
/// (`verse_of_day_history_sheet.dart`): a "Previous verse of the day"
/// header over a paginated, purely browsable list of past verses — each row
/// is its own mini background-image card (reusing `VerseOfDayBackgroundImageView`/
/// `VerseOfDayScrimOverlay` from `VerseOfDayCardView.swift`) with the verse
/// text, its book/chapter/verse reference, and the date it was sent.
///
/// Deliberately no tap-to-select-as-today and no long-press options sheet:
/// confirmed against the Dart source, which wires neither on these rows —
/// this list is read-only browsing, not a way to re-surface an old verse as
/// "today's" card. Only the verse text itself is tappable, navigating to
/// that verse's own place in the reader (`VerseOfDayContentUi`'s `InkWell`,
/// the same `DashboardNavigateTo(4)` + reader-content-changed pattern
/// `VerseOfDayCardView.navigateToReader()` already ports).
struct VerseOfDayHistorySheet: View {
    @State private var viewModel = VerseOfDayHistoryViewModel()

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Previous verse of the day")
                .typography(Typography.bodyLarge)
                .foregroundStyle(theme.color(.textSecondary))
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            content
        }
        .task {
            await viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingHistory, !viewModel.hasLoadedOnce {
            LoadingStateView()
        } else if viewModel.hasLoadedOnce, viewModel.verses.isEmpty {
            EmptyStateView(title: "No previous verses yet")
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.lg) {
                    ForEach(viewModel.verses) { verse in
                        VerseOfDayHistoryRow(verse: verse)
                            .onAppear {
                                Task { await viewModel.loadMoreHistoryIfNeeded(currentItem: verse) }
                            }
                    }
                    if viewModel.isLoadingHistory {
                        LoadingStateView()
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
        }
    }
}

/// One past verse's mini card. Ports the Dart list item's `Stack` of
/// `VerseOfDayBgWidget` + `VerseOfDayBgGradiant` + content/meta/date column.
private struct VerseOfDayHistoryRow: View {
    let verse: VerseOfDay

    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private var backgroundURL: URL? {
        ArtworkURLResolver().resolve(path: verse.backgroundImage, variant: .lg, allowedVariants: nil)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VerseOfDayBackgroundImageView(url: backgroundURL)
                .opacity(0.8)
            VerseOfDayScrimOverlay()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("VERSE OF THE DAY")
                    .typography(Typography.labelSmall)
                    .foregroundStyle(theme.color(.textInverse).opacity(0.8))

                Button(action: navigateToReader) {
                    Text(verse.verseText ?? "")
                        .typography(Typography.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.color(.textInverse))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(verse.bookNumber == nil || verse.chapterNumber == nil)

                HStack(alignment: .bottom) {
                    if let reference = verse.reference {
                        Text(reference)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(theme.color(.textInverse).opacity(0.8))
                    }
                    Spacer(minLength: Spacing.sm)
                    if let sentAt = verse.sentAt {
                        Text(Self.dateFormatter.string(from: sentAt))
                            .typography(Typography.bodySmall)
                            .foregroundStyle(theme.color(.textInverse).opacity(0.8))
                    }
                }
            }
            .padding(Spacing.md)
        }
        .frame(minHeight: 140)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func navigateToReader() {
        guard let bookNumber = verse.bookNumber, let chapterNumber = verse.chapterNumber else { return }
        coordinator.selectedTab = .read
        navigationStore.pendingTarget = ReaderNavigationStore.Target(bookNumber: bookNumber, chapterNumber: chapterNumber)
    }
}
