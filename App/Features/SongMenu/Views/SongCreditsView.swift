import SwiftUI

/// `SongCreditPage` (`lib/sheets/song/song_credit_sheet.dart`): credits
/// grouped under category headings, with loading, empty and failed states.
struct SongCreditsView: View {
    let viewModel: SongMenuViewModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        // Flutter draws no heading: just the drag handle, then the groups.
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, 12)
        .task { await viewModel.loadCredits() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.credits {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: Spacing.xxl)
        case .failed:
            message("Failed to load credits.\nPlease try again.")
        case .loaded(let groups) where groups.isEmpty:
            message(viewModel.isEpisode ? "No credits available for this episode." : "No credits available for this song.")
        case .loaded(let groups):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.category) { group in
                        section(group)
                    }
                }
            }
        }
    }

    /// `_buildCategorySection`: `titleMedium` w600 white with 12 / 8 padding,
    /// dense role / name tiles, 12pt after the group.
    private func section(_ group: SongCreditGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.category)
                .typography(PlayerStyle.titleMediumSemibold)
                .foregroundStyle(PlayerStyle.white)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ForEach(Array(group.credits.enumerated()), id: \.offset) { _, credit in
                VStack(alignment: .leading, spacing: 0) {
                    Text(credit.role ?? "")
                        .typography(TypographyToken(size: 16, weight: .bold, lineHeightMultiple: 1.5))
                        .foregroundStyle(PlayerStyle.white)
                    Text(credit.name ?? "-")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(PlayerStyle.whiteAlpha(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            Spacer().frame(height: 12)
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .typography(Typography.bodyMedium)
            .foregroundStyle(theme.color(.textSecondary))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Spacing.xxl)
    }
}
