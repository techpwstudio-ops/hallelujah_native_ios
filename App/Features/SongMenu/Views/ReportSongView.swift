import SwiftUI

/// `showReportSheet` (`lib/sheets/song/report_song_sheet.dart`): "Enter
/// Reason" heading, a 6-8 line free-text box (`ColorTheme.dark` fill, radius 8,
/// hint `#808080`), then a filled white "Report" button and an outlined
/// "Cancel" button, 16pt apart. An empty box toasts "Please enter note", a
/// blank one "Please enter a reason and try again";.
struct ReportSongView: View {
    let viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    @State private var reason = ""
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter Reason")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            Spacer().frame(height: 8)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reason)
                    .scrollContentBackground(.hidden)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 0)
                if reason.isEmpty {
                    Text("Enter Reason")
                        .typography(Typography.bodySmall)
                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .background(theme.color(.surfaceInput), in: RoundedRectangle(cornerRadius: Dimens.cornerRadius))
            Spacer().frame(height: 24)
            AppButton(label: "Report", action: send, isLoading: viewModel.isBusy)
            Spacer().frame(height: 16)
            AppButton.secondary("Cancel", enabled: !viewModel.isBusy) { onOutcome(.dismiss) }
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.vertical, Spacing.md)
    }

    private func send() {
        Task {
            onOutcome(await viewModel.report(reason: reason))
        }
    }
}
