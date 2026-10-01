import SwiftUI
import UIKit

/// Generic share sheet for T68 — every entry point (`FullPlayerView`,
/// `CreatorProfileView`, `PlaylistDetailView`) presents this same view via
/// `.appSheet`, differing only in `target`/`title`/`subtitle`/`artworkURL`.
///
/// Covers every live Flutter share target except the dead "status share"
/// path (`_buildStatusSection()` is commented out in the Dart source) and
/// AI-message/plain-creator-playlist sharing, neither of which the Flutter
/// app itself supports either.
struct ShareSheetView: View {
    let target: ShareTarget
    let title: String
    let subtitle: String?
    let artworkURL: URL?

    @State private var viewModel: ShareSheetViewModel
    @State private var selectedTheme: ShareCardTheme = .crimson
    @State private var confirmationMessage: String?
    @Environment(\.appTheme) private var theme

    init(target: ShareTarget, title: String, subtitle: String?, artworkURL: URL?) {
        self.target = target
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        _viewModel = State(initialValue: ShareSheetViewModel(target: target))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                LoadingStateView(message: "Preparing to share…")
            case .failed:
                ErrorStateView(
                    title: "Couldn't create share link",
                    onRetry: { Task { await viewModel.retry() } }
                )
            case .loaded(let url):
                loadedContent(baseURL: url)
            }
        }
        .padding(.bottom, Spacing.xl)
        .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private func loadedContent(baseURL: URL) -> some View {
        let sharedURL = versionedURL(baseURL)

        ScrollView {
            VStack(spacing: Spacing.lg) {
                ShareCardView(theme: selectedTheme, title: title, subtitle: subtitle, artworkURL: artworkURL)
                    .padding(.top, Spacing.sm)

                themePicker

                chatAppsRow(url: sharedURL)

                actionButtonsRow(url: sharedURL)

                confirmationLabel
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    private var themePicker: some View {
        HStack(spacing: Spacing.md) {
            ForEach(ShareCardTheme.allCases, id: \.self) { cardTheme in
                Button {
                    selectedTheme = cardTheme
                } label: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: cardTheme.gradientColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    theme.color(.textPrimary),
                                    lineWidth: selectedTheme == cardTheme ? 2 : 0
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cardTheme.title)
            }
        }
    }

    private func chatAppsRow(url: URL) -> some View {
        HStack(spacing: Spacing.lg) {
            iconButton(systemImage: "message.fill", label: "WhatsApp") {
                open(scheme: "whatsapp://send?text=\(shareText(url: url))")
            }
            iconButton(systemImage: "paperplane.fill", label: "Telegram") {
                open(scheme: "tg://msg?text=\(shareText(url: url))")
            }
            iconButton(systemImage: "at", label: "Twitter") {
                open(scheme: "twitter://post?message=\(shareText(url: url))")
            }
            Spacer()
        }
    }

    private func actionButtonsRow(url: URL) -> some View {
        HStack(spacing: Spacing.lg) {
            iconButton(systemImage: "doc.on.doc", label: "Copy Link") {
                UIPasteboard.general.string = url.absoluteString
                showConfirmation("Link copied")
            }
            iconButton(systemImage: "square.and.arrow.down", label: "Save Image") {
                Task { await saveImage() }
            }
            ShareLink(item: url) {
                iconButtonLabel(systemImage: "square.and.arrow.up", label: "More")
            }
            Spacer()
        }
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconButtonLabel(systemImage: systemImage, label: label)
        }
        .buttonStyle(.plain)
    }

    private func iconButtonLabel(systemImage: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(theme.color(.textPrimary))
                .frame(width: 48, height: 48)
                .background(theme.color(.surfaceSecondary))
                .clipShape(Circle())
            Text(label)
                .typography(Typography.labelSmall)
                .foregroundStyle(theme.color(.textSecondary))
        }
    }

    @ViewBuilder
    private var confirmationLabel: some View {
        if let confirmationMessage {
            Text(confirmationMessage)
                .typography(Typography.labelMedium)
                .foregroundStyle(theme.color(.textSecondary))
                .transition(.opacity)
        }
    }

    /// `?viewType=` so a recipient's link-preview/OG-crawler image matches
    /// the theme picked here, even though this app never re-fetches that
    /// server-composited card itself (see `ShareCardTheme`'s own doc comment).
    private func versionedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "viewType", value: selectedTheme.variantKey))
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private func shareText(url: URL) -> String {
        let text = "\(title) — \(url.absoluteString)"
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+")
        return text.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? text
    }

    /// No `canOpenURL` guard, matching every other `UIApplication.shared.open`
    /// call site in this codebase — none of the four precedents check first.
    private func open(scheme: String) {
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func saveImage() async {
        let resolvedArtwork: UIImage? = if let artworkURL {
            await ArtworkImageCache.shared.image(for: artworkURL, maxPixelSize: 400)
        } else {
            nil
        }

        let renderer = ImageRenderer(
            content: ShareCardView(
                theme: selectedTheme,
                title: title,
                subtitle: subtitle,
                artworkURL: artworkURL,
                resolvedArtwork: resolvedArtwork
            )
        )
        renderer.scale = 3

        guard let uiImage = renderer.uiImage else {
            showConfirmation("Couldn't save image")
            return
        }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        showConfirmation("Saved to Photos")
    }

    private func showConfirmation(_ message: String) {
        withAnimation { confirmationMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { confirmationMessage = nil }
        }
    }
}
