import SwiftUI

/// `showReportSongSheet` (`lib/sheets/song/report_song_sheet.dart`): a single
/// free-text reason and a Send button. Blank reasons are refused by the view
/// model with the same wording Dart toasts.
struct ReportSongView: View {
    let viewModel: SongMenuViewModel
    let onOutcome: (SongMenuOutcome) -> Void

    @State private var reason = ""
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Enter Reason")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            AppTextField(text: $reason, placeholder: "Enter Reason")
            AppButton(label: "Send", action: send, isLoading: viewModel.isBusy)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    private func send() {
        Task { onOutcome(await viewModel.report(reason: reason)) }
    }
}
