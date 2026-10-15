import SwiftUI

/// `showVerseOfDayHistory` (`lib/sheets/book/verse_of_day_history_sheet.dart`):
/// drag handle, "Previous verse of the day" (bodyLarge, white 70%, 24pt side
/// padding), a 12pt gap, then one artwork card per past verse (16pt apart):
/// the "VERSE OF THE DAY" label, the quoted verse, and a row with the
/// "Book . ch . v" line and the dd/MM/yyyy date. Spinner while loading, the
/// default `Empty` text ("No Record Founds.") when there is none.
struct VerseOfDayHistorySheet: View {
    @State private var viewModel = VerseOfDayHistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadDragHandle()

            Text("Previous verse of the day")
                .readText(Typography.bodyLarge, weight: .regular, color: ReadPalette.secondaryText)
                .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            content
        }
        .task {
            await viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingHistory, !viewModel.hasLoadedOnce {
            ReadSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasLoadedOnce, viewModel.verses.isEmpty {
            ReadEmptyText(text: "No Record Founds.")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.verses.filter { $0.verseText != nil }) { verse in
                        VerseOfDayHistoryRow(verse: verse)
                            .onAppear {
                                Task { await viewModel.loadMoreHistoryIfNeeded(currentItem: verse) }
                            }
                    }
                    if viewModel.isLoadingHistory {
                        ReadSpinner()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct VerseOfDayHistoryRow: View {
    let verse: VerseOfDay

    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return formatter
    }()

    private var backgroundURL: URL? {
        ArtworkURLResolver().resolve(path: verse.backgroundImage, variant: .lg, allowedVariants: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VerseOfDayContentBlock(verse: verse, onVerseTap: navigateToReader)
            HStack(alignment: .bottom, spacing: 0) {
                VerseOfDayMetaText(verse: verse)
                    .fixedSize()
                Spacer(minLength: 8)
                if let sentAt = verse.sentAt {
                    Text(Self.dateFormatter.string(from: sentAt))
                        .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body))
                        .foregroundStyle(ReadPalette.white)
                }
            }
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
