import SwiftUI

/// `startBibleOfflineDownload` (`lib/widgets/book/bible_offline_download_button.dart`):
/// safe to call for a language in any state — already saved or already
/// downloading says so in a toast instead of starting twice, and offline says
/// so before trying.
@MainActor
func startBibleOfflineDownload(
    language: String,
    service: BibleOfflineDownloadService,
    toast: ToastCenter
) async {
    if service.isLanguageDownloaded(language) {
        toast.show("The \(language) Bible is already saved on this device.")
        return
    }
    if service.isDownloading(language) {
        toast.show("The \(language) Bible is already downloading.")
        return
    }
    let reachability: any ReachabilityMonitoring = DependencyContainer.current.resolve()
    if !reachability.isOnline {
        toast.show("You need an internet connection to save the \(language) Bible for offline reading.")
        return
    }
    // No toast on start — the ring is the feedback (matches Flutter).
    await service.downloadLanguage(language, announce: true)
}

/// The control that saves one Bible language for offline reading and doubles
/// as that language's status: outlined download icon (white 70%), a progress
/// ring (white on white 24% track, 2pt) while downloading, a filled check
/// (white) once saved — long-pressed to remove. All three draw in the same
/// `size` box so nothing shifts as one becomes the next.
struct BibleOfflineDownloadButton: View {
    let language: String
    var size: CGFloat = 24

    @Environment(\.toastCenter) private var toastCenter
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
                Task { await startBibleOfflineDownload(language: language, service: service, toast: toastCenter) }
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
                    Task {
                        let removed = await service.deleteLanguage(language)
                        if removed {
                            toastCenter.show("\(language) Bible removed from this device.")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove the \(language) Bible from this device? You'll need to download it again to read it offline.")
            }
    }

    @ViewBuilder
    private var indicator: some View {
        if isDownloading {
            // Determinate once the book count is known, indeterminate before
            // (`active.total > 0 ? active.fraction : null`).
            if let progress, progress.total > 0 {
                BibleOfflineRing(fraction: progress.fraction)
            } else {
                BibleOfflineRing(fraction: nil)
            }
        } else if isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(ReadPalette.white)
        } else {
            // `Icons.download_for_offline_outlined`.
            Image(systemName: "arrow.down.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(ReadPalette.white70)
        }
    }

    private var accessibilityLabel: String {
        if isDownloading {
            let percent = progress?.percent ?? 0
            return "Saving \(language) Bible, \(percent) percent done"
        }
        if isDownloaded {
            return "\(language) Bible is saved on this device. Long press to remove it."
        }
        return "Save \(language) Bible on this device"
    }
}

/// `CircularProgressIndicator(strokeWidth: 2, color: white, backgroundColor: white24)`.
private struct BibleOfflineRing: View {
    let fraction: Double?

    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(ReadPalette.white24, lineWidth: 2)
            if let fraction {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0.02), 1)))
                    .stroke(ReadPalette.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(ReadPalette.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotating)
                    .onAppear { rotating = true }
            }
        }
        .padding(1)
    }
}
