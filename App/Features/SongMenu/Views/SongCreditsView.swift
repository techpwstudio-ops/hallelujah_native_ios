import SwiftUI

/// `SongCreditPage` (`lib/sheets/song/song_credit_sheet.dart`): credits
/// grouped under category headings, with loading, empty and failed states.
struct SongCreditsView: View {
    let viewModel: SongMenuViewModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Credits")
                .typography(Typography.titleLarge)
                .foregroundStyle(theme.color(.textPrimary))
            content
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
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
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(groups, id: \.category) { group in
                        section(group)
                    }
                }
            }
        }
    }

    private func section(_ group: SongCreditGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(group.category)
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.brandPrimary))
            ForEach(Array(group.credits.enumerated()), id: \.offset) { _, credit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.role ?? "")
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                    Text(credit.name ?? "-")
                        .typography(Typography.bodyLarge)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            }
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
