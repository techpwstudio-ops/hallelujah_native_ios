import Photos
import SwiftUI
import UIKit

/// Generic share sheet (`showShareSheet` / `ShareSheet`,
/// `lib/sheets/share/show_content_share_sheet.dart`): `fillColor` card with a
/// 24pt top radius, 8pt top gap, drag handle, themed story-card preview,
/// 24pt gradient-circle theme picker, then a wrap of 52pt circular actions
/// (installed chat apps, Copy Link, Save Image, More). The "Share as Story"
/// section is commented out in Flutter and so omitted here. AI-answer and
/// verse card types are not rendered by this view (Bible verses have their own
/// editor, `BibleVerseShareView`).
///
/// `aspectRatio` "16:9" selects the wide card (`_Landscape16x9Preview`).
struct ShareSheetView: View {
    let target: ShareTarget
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var aspectRatio: String = "1:1"

    @State private var viewModel: ShareSheetViewModel
    @State private var selectedTheme: ShareCardTheme = .crimson
    @State private var confirmationMessage: String?
    @State private var installedChatApps: [ChatApp] = []
    @State private var isSavingImage = false
    @State private var isPhotoAccessDialogPresented = false

    init(target: ShareTarget, title: String, subtitle: String?, artworkURL: URL?, aspectRatio: String = "1:1") {
        self.target = target
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.aspectRatio = aspectRatio
        _viewModel = State(initialValue: ShareSheetViewModel(target: target))
    }

    struct ChatApp: Identifiable, Equatable {
        let name: String
        let systemImage: String
        let scheme: String
        var id: String { scheme }
    }

    /// `_kChatApps` (SVG assets stood in by SF Symbols).
    private static let chatApps: [ChatApp] = [
        ChatApp(name: "WhatsApp", systemImage: "message.circle.fill", scheme: "whatsapp"),
        ChatApp(name: "Telegram", systemImage: "paperplane.circle.fill", scheme: "tg"),
        ChatApp(name: "Twitter", systemImage: "bird", scheme: "twitter"),
    ]

    private var isLandscape: Bool { aspectRatio == "16:9" }

    /// 1:1 -> `screenWidth * 0.8`; 16:9 -> `screenWidth - 40`.
    private var cardWidth: CGFloat {
        let screen = UIScreen.main.bounds.width
        return isLandscape ? screen - Dimens.spacing40 : screen * 0.8
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .tint(AccountParity.white)
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed:
                VStack(spacing: Dimens.spacing12) {
                    Text("Couldn't create share link")
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.white)
                    ParityFilledButton(title: "Retry") { Task { await viewModel.retry() } }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            case .loaded(let url):
                loadedContent(baseURL: url)
            }
        }
        .background(AccountParity.fill)
        .task { await viewModel.loadIfNeeded() }
        .task { await detectInstalledChatApps() }
        .fullScreenCover(isPresented: $isPhotoAccessDialogPresented) {
            ParityConfirmationDialog(
                title: "Photo access",
                message: "Allow photo access in Settings to save this image to your device.",
                systemIcon: "photo.on.rectangle",
                onCancel: { isPhotoAccessDialogPresented = false },
                onConfirm: {
                    isPhotoAccessDialogPresented = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
            .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func loadedContent(baseURL: URL) -> some View {
        let sharedURL = versionedURL(baseURL)

        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: Dimens.spacing8)
                ParityDragHandler()
                Spacer().frame(height: Dimens.spacing20)

                ShareCardView(
                    theme: selectedTheme,
                    title: title,
                    subtitle: subtitle,
                    artworkURL: artworkURL,
                    cardWidth: cardWidth,
                    isLandscape: isLandscape
                )
                .shadow(color: selectedTheme.gradientColors[0].opacity(0.5), radius: Dimens.spacing24 / 2, x: 0, y: Dimens.spacing8)

                Spacer().frame(height: Dimens.spacing16)
                themePicker
                Spacer().frame(height: Dimens.spacing24)

                actions(url: sharedURL)
                    .padding(.horizontal, Dimens.spacing20)

                confirmationLabel

                Spacer().frame(height: Dimens.spacing32)
            }
        }
    }

    // MARK: Theme picker (`_ThemeSelector`)

    private var themePicker: some View {
        HStack(spacing: 0) {
            ForEach(ShareCardTheme.allCases, id: \.self) { cardTheme in
                let isSelected = selectedTheme == cardTheme
                Button {
                    selectedTheme = cardTheme
                } label: {
                    Circle()
                        .fill(LinearGradient(
                            colors: cardTheme.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: Dimens.spacing24, height: Dimens.spacing24)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? AccountParity.white : AccountParity.white24,
                                lineWidth: isSelected ? Dimens.spacing2 : Dimens.borderWidth
                            )
                        )
                        .shadow(
                            color: isSelected ? cardTheme.gradientColors[0].opacity(0.55) : Color.clear,
                            radius: Dimens.spacing8 / 2
                        )
                        .padding(.trailing, Dimens.spacing8)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
                .accessibilityLabel(cardTheme.title)
            }
        }
        .frame(height: Dimens.spacing24)
    }

    // MARK: Actions (`_buildChatSection`)

    private func actions(url: URL) -> some View {
        WrapLayout(spacing: Dimens.spacing16, lineSpacing: Dimens.spacing16) {
            ForEach(installedChatApps) { app in
                shareIcon(label: app.name) {
                    Image(systemName: app.systemImage)
                        .font(.system(size: Dimens.iconSize))
                        .foregroundStyle(AccountParity.white)
                } action: {
                    shareToChatApp(app, url: url)
                }
            }
            shareIcon(label: "Copy Link") {
                Image(systemName: "link")
                    .font(.system(size: Dimens.iconSize))
                    .foregroundStyle(AccountParity.white)
            } action: {
                UIPasteboard.general.string = url.absoluteString
                showConfirmation("Link copied")
            }
            shareIcon(label: "Save Image") {
                if isSavingImage {
                    ProgressView().tint(AccountParity.white60)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: Dimens.iconSize))
                        .foregroundStyle(AccountParity.white)
                }
            } action: {
                Task { await saveImage() }
            }
            ShareLink(item: url) {
                shareIconLabel(label: "More") {
                    Image(systemName: "ellipsis")
                        .font(.system(size: Dimens.iconSize))
                        .foregroundStyle(AccountParity.white)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `_ShareIcon`: 52pt white10 circle with white12 border, 8pt gap, 60pt-wide
    /// 10pt white60 label.
    private func shareIcon<Icon: View>(label: String, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            shareIconLabel(label: label, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func shareIconLabel<Icon: View>(label: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: Dimens.spacing8) {
            icon()
                .frame(width: Dimens.buttonHeight, height: Dimens.buttonHeight)
                .background(Circle().fill(AccountParity.white10))
                .overlay(Circle().strokeBorder(AccountParity.white12, lineWidth: 1))
            Text(label)
                .font(AccountParity.font(10))
                .lineSpacing(3)
                .foregroundStyle(AccountParity.white60)
                .multilineTextAlignment(.center)
                .frame(width: Dimens.spacing60)
        }
    }

    @ViewBuilder
    private var confirmationLabel: some View {
        if let confirmationMessage {
            Text(confirmationMessage)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AccountParity.white))
                .padding(.top, Dimens.spacing16)
                .transition(.opacity)
        }
    }

    // MARK: Behaviour

    /// `?viewType=` so a recipient's OG-crawler image matches the picked theme.
    private func versionedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "viewType", value: selectedTheme.variantKey))
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    /// `_isAppInstalled` -> `canLaunchUrl('<scheme>://')`. Requires the schemes
    /// in `LSApplicationQueriesSchemes`.
    private func detectInstalledChatApps() async {
        let installed = Self.chatApps.filter { app in
            guard let url = URL(string: "\(app.scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        installedChatApps = installed
    }

    /// `_shareToChatApp`: title, subtitle, versioned url joined by newlines,
    /// `Uri.encodeComponent`-encoded into each app's URL scheme.
    private func shareToChatApp(_ app: ChatApp, url: URL) {
        var lines: [String] = []
        if !title.isEmpty { lines.append(title) }
        if let subtitle, !subtitle.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(subtitle.trimmingCharacters(in: .whitespaces))
        }
        lines.append(url.absoluteString)
        let text = lines.joined(separator: "\n")

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text

        let raw: String
        switch app.scheme {
        case "whatsapp": raw = "whatsapp://send?text=\(encoded)"
        case "tg": raw = "tg://msg?text=\(encoded)"
        default: raw = "twitter://post?message=\(encoded)"
        }
        guard let target = URL(string: raw) else {
            showConfirmation("\(app.name) not supported")
            return
        }
        UIApplication.shared.open(target) { success in
            if !success {
                Task { @MainActor in showConfirmation("\(app.name) not available") }
            }
        }
    }

    /// `_downloadImage`: ask for photo access (add-only), explain via the
    /// "Photo access" dialog if denied, render the card at 3x and save it.
    @MainActor
    private func saveImage() async {
        guard !isSavingImage else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isPhotoAccessDialogPresented = true
            return
        }

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
                cardWidth: cardWidth,
                isLandscape: isLandscape,
                resolvedArtwork: resolvedArtwork
            )
        )
        renderer.scale = 3

        guard let uiImage = renderer.uiImage else {
            showConfirmation("Couldn\u{2019}t create the image. Please try again.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }
            showConfirmation("Saved to Photos")
        } catch {
            showConfirmation("Couldn\u{2019}t save the image. Please try again.")
        }
    }

    private func showConfirmation(_ message: String) {
        withAnimation { confirmationMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { confirmationMessage = nil }
        }
    }
}

/// Minimal `Wrap` for the action grid.
private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
