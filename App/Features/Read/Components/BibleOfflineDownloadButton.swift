import SwiftUI

/// T55 — tri-state offline-download control, ported from
/// `bible_offline_download_button.dart`'s one shared button (used in both
/// the Bible menu and the language picker), so a language looks the same
/// wherever it's shown: an outlined icon to download it, a ring while it
/// downloads, a filled checkmark once it's on the device. Tap only starts a
/// download from the `notSaved` state; long-press only removes from the
/// `saved` state — the `downloading` state responds to neither, mirroring
/// Dart's `InkResponse(onTap: tappable ? ... : null, onLongPress: removable
/// ? ... : null)`.
///
/// Scope cut from Dart's `startBibleOfflineDownload`: no "already saved" /
/// "already downloading" / "no internet" toast before starting — this
/// button relies on `BibleOfflineDownloadService.downloadLanguage`'s own
/// idempotent join behavior instead (a second tap while downloading is a
/// no-op via `isDownloading`, so no separate messaging is load-bearing).
struct BibleOfflineDownloadButton: View {
    let language: String
    var size: CGFloat = 24

    @Environment(\.appTheme) private var theme
    @State private var service: BibleOfflineDownloadService = DependencyContainer.current.resolve()
    @State private var isRemoveConfirmationPresented = false

    private var isDownloaded: Bool { service.isLanguageDownloaded(language) }
    private var isDownloading: Bool { service.isDownloading(language) }
    private var progress: BibleOfflineProgress? { service.status.progress(for: language) }

    var body: some View {
        indicator
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onTapGesture {
                guard !isDownloaded, !isDownloading else { return }
                Task { await service.downloadLanguage(language) }
            }
            .onLongPressGesture {
                guard isDownloaded else { return }
                isRemoveConfirmationPresented = true
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .confirmationDialog(
                "Remove Bible",
                isPresented: $isRemoveConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task { await service.deleteLanguage(language) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove the \(language) Bible from this device? You'll need to download it again to read it offline.")
            }
    }

    @ViewBuilder
    private var indicator: some View {
        if isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .foregroundStyle(theme.color(.textPrimary))
        } else if isDownloading {
            // Determinate as soon as the book count is known, matching
            // Dart's `active.total > 0 ? active.fraction : null` (indeterminate
            // spinner briefly, until the first book count arrives).
            if let progress, progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        } else {
            theme.icon(.download)
                .resizable()
                .foregroundStyle(theme.color(.textSecondary))
        }
    }

    private var accessibilityLabel: String {
        if isDownloaded {
            return "\(language) Bible is saved on this device. Long press to remove it."
        }
        if isDownloading {
            let percent = Int(((progress?.fraction ?? 0) * 100).rounded())
            return "Saving \(language) Bible, \(percent) percent done"
        }
        return "Save \(language) Bible on this device"
    }
}
