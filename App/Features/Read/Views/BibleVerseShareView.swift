import Photos
import PhotosUI
import SwiftUI
import UIKit

/// `BibleVerseSharePage` (`lib/views/read/bible_verse_share_page.dart`) — the
/// full-screen "Status"-style editor for sharing a verse. Black page; top bar
/// (close, centred "Share verse", 48pt spacer); the 9:16 card preview (40/12
/// padding, 16pt radius) taking whatever height the controls leave; then the
/// BACKGROUND swatch row (photo first, then six presets), photo chips, an
/// inline saved/failed notice, a gold "Share card" button and a row of
/// "Save image" / "Text only" tiles. The card is laid out on a 360x640 canvas
/// (design width 300, scaled 1.2x) so the preview equals the 1080x1920 export.
///
/// Platform gaps (documented): the verse serif is the system serif (Literata
/// is not bundled), and the saved image goes to the camera roll without the
/// app's named album.
struct BibleVerseShareView: View {
    let verseReference: String
    let verseText: String
    let deepLinkURL: String

    @Environment(\.dismiss) private var dismiss

    private enum ShareAction {
        case shareCard, saveImage, shareText
    }

    private enum NoticeKind: Equatable {
        case saved
        case failed(message: String, retry: Int)
    }

    @State private var presetIndex = 0
    @State private var photo: UIImage?
    @State private var usePhoto = false
    @State private var working: ShareAction?
    @State private var notice: NoticeKind?
    @State private var noticeTask: Task<Void, Never>?
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var activityItems: ActivityItems?
    @State private var showPhotoAccess = false

    private var isBusy: Bool { working != nil }
    private var photoSelected: Bool { usePhoto && photo != nil }

    private var shareMessage: String {
        let trimmedVerse = verseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "\u{201C}\(trimmedVerse)\u{201D}\n\u{2014} \(verseReference)\n\n\(deepLinkURL)")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
                .frame(maxHeight: .infinity)
            controls
                // Native-only tablet/Mac adaptation: the controls keep the
                // preview card's column instead of spanning the window.
                .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
        }
        .background(ReadPalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        // Once the system share sheet is done (shared, copied or
        // cancelled), the editor has done its job: close it too rather than
        // leave it on screen behind.
        .sheet(item: $activityItems, onDismiss: { dismiss() }) { items in
            ActivityView(items: items.values) { activityItems = nil }
        }
        .readSheet(isPresented: $showPhotoAccess, detents: [.height(380)], cornerRadius: Dimens.spacing24) {
            VersePhotoAccessSheet(
                onOpenSettings: {
                    showPhotoAccess = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                onUseColour: { showPhotoAccess = false }
            )
        }
        .onDisappear { noticeTask?.cancel() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ReadPalette.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text("Share verse")
                .readText(Typography.titleSmall)
                .frame(maxWidth: .infinity)

            Spacer().frame(width: Dimens.spacing48)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { proxy in
            // Native-only tablet/Mac adaptation: on a tall iPad the card would
            // otherwise grow with the window; it stops at the media column.
            let availableWidth = max(AdaptiveLayout.proportionalWidth(proxy.size.width) - Dimens.spacing40 * 2, 1)
            let availableHeight = max(proxy.size.height - Dimens.spacing12 * 2, 1)
            let ratio = Dimens.verseCardCanvasWidth / Dimens.verseCardCanvasHeight
            let width = min(availableWidth, availableHeight * ratio)
            let scale = width / Dimens.verseCardCanvasWidth
            let height = Dimens.verseCardCanvasHeight * scale

            VerseShareCardView(
                verseText: verseText,
                verseReference: verseReference,
                background: ReadPalette.verseCardBackgrounds[presetIndex],
                photo: photoSelected ? photo : nil
            )
            .frame(width: Dimens.verseCardCanvasWidth, height: Dimens.verseCardCanvasHeight)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Dimens.verseCardPreviewRadius, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Background".uppercased())
                    .typography(Typography.labelSmall)
                    .fontWeight(.semibold)
                    .tracking(1.2)
                    .foregroundStyle(ReadPalette.white45)
                    .padding(.horizontal, Dimens.spacing16)

                Spacer().frame(height: Dimens.spacing8)

                backgroundPicker

                if photoSelected {
                    HStack(spacing: Dimens.spacing8) {
                        VersePhotoChip(systemName: "slider.horizontal.3", label: "Change photo") {
                            pickPhoto()
                        }
                        VersePhotoChip(systemName: "trash", label: "Remove") {
                            photo = nil
                            usePhoto = false
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(EdgeInsets(top: Dimens.spacing12, leading: Dimens.spacing16, bottom: 0, trailing: Dimens.spacing16))
                }
            }
            .opacity(isBusy ? 0.4 : 1)
            .allowsHitTesting(!isBusy)
            .animation(.easeInOut(duration: 0.2), value: isBusy)

            if let notice {
                noticeView(notice)
                    .padding(EdgeInsets(top: Dimens.spacing12, leading: Dimens.spacing16, bottom: 0, trailing: Dimens.spacing16))
            }

            Spacer().frame(height: Dimens.spacing12)

            VerseShareButton(
                primary: true,
                systemName: "square.and.arrow.up",
                label: "Share card",
                hint: "Image + verse and app link",
                busy: working == .shareCard,
                busyLabel: "Preparing image\u{2026}",
                enabled: !isBusy,
                action: { Task { await shareCard() } }
            )
            .padding(.horizontal, Dimens.spacing16)

            Spacer().frame(height: Dimens.spacing8)

            HStack(spacing: Dimens.spacing8) {
                VerseShareButton(
                    primary: false,
                    systemName: "arrow.down.to.line",
                    label: "Save image",
                    hint: "To your gallery",
                    busy: working == .saveImage,
                    busyLabel: "Saving\u{2026}",
                    enabled: !isBusy,
                    action: { Task { await saveImage() } }
                )
                VerseShareButton(
                    primary: false,
                    systemName: "quote.opening",
                    label: "Text only",
                    hint: "No image, low data",
                    busy: working == .shareText,
                    busyLabel: nil,
                    enabled: !isBusy,
                    action: { shareText() }
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Dimens.spacing16)
        }
        .padding(.bottom, Dimens.spacing12)
        // Flutter wraps the photo chips and the notice in 200ms `AnimatedSize`.
        .animation(.easeInOut(duration: 0.2), value: photoSelected)
        .animation(.easeInOut(duration: 0.2), value: notice)
    }

    private var backgroundPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Dimens.spacing8) {
                VerseSwatch(selected: photoSelected, label: "Photo background", action: onPhotoSwatchTap) {
                    PhotoSwatchArt(photo: photo)
                }
                ForEach(0..<ReadPalette.verseCardBackgrounds.count, id: \.self) { index in
                    VerseSwatch(
                        selected: !photoSelected && presetIndex == index,
                        label: "Colour background \(index + 1)",
                        action: {
                            presetIndex = index
                            usePhoto = false
                        }
                    ) {
                        VerseCardBackground(colors: ReadPalette.verseCardBackgrounds[index])
                    }
                }
            }
            .padding(.horizontal, Dimens.spacing16)
        }
        .frame(height: Dimens.verseShareSwatchSize)
    }

    @ViewBuilder
    private func noticeView(_ kind: NoticeKind) -> some View {
        switch kind {
        case .saved:
            VerseShareNotice(
                failed: false,
                message: String(localized: "Saved to Photos"),
                detail: String(localized: "Hallelujah album"),
                actionLabel: nil,
                action: {}
            )
        case .failed(let message, _):
            VerseShareNotice(
                failed: true,
                message: message,
                detail: nil,
                actionLabel: String(localized: "Retry"),
                action: { retryLast() }
            )
        }
    }

    // MARK: - Background

    /// Picks a photo the first time; afterwards switches back to it, and a tap
    /// on the already-selected photo swaps it for another.
    private func onPhotoSwatchTap() {
        if photo == nil || photoSelected {
            pickPhoto()
        } else {
            usePhoto = true
        }
    }

    private func pickPhoto() {
        guard !isBusy else { return }
        showPhotoPicker = true
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photo = image
        usePhoto = true
    }

    // MARK: - Actions

    @State private var failedAction: ShareAction?

    private func retryLast() {
        switch failedAction {
        case .shareCard: Task { await shareCard() }
        case .saveImage: Task { await saveImage() }
        case .shareText: shareText()
        case nil: break
        }
    }

    private func start(_ action: ShareAction) -> Bool {
        if isBusy { return false }
        noticeTask?.cancel()
        working = action
        notice = nil
        return true
    }

    private func finish(notice newNotice: NoticeKind?, action: ShareAction) {
        working = nil
        notice = newNotice
        if case .failed = newNotice {
            failedAction = action
        }
        if case .saved = newNotice {
            noticeTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                notice = nil
            }
        }
    }

    private func shareCard() async {
        guard start(.shareCard) else { return }
        // Let the "preparing" state paint before the (main-actor) render.
        try? await Task.sleep(for: .milliseconds(50))
        guard let url = captureCardToFile() else {
            finish(
                notice: .failed(message: String(localized: "Couldn't create the image. Your verse is safe \u{2014} try again."), retry: 0),
                action: .shareCard
            )
            return
        }
        activityItems = ActivityItems(values: [url, shareMessage])
        finish(notice: nil, action: .shareCard)
    }

    private func shareText() {
        guard start(.shareText) else { return }
        activityItems = ActivityItems(values: [shareMessage])
        finish(notice: nil, action: .shareText)
    }

    private func saveImage() async {
        guard start(.saveImage) else { return }
        try? await Task.sleep(for: .milliseconds(50))
        guard let image = renderCard(), let data = image.pngData() else {
            finish(
                notice: .failed(message: String(localized: "Couldn't create the image. Your verse is safe \u{2014} try again."), retry: 0),
                action: .saveImage
            )
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            finish(notice: nil, action: .saveImage)
            showPhotoAccess = true
            return
        }
        do {
            try await PhotoLibrarySaver.save(imageData: data)
            finish(notice: .saved, action: .saveImage)
        } catch {
            finish(
                notice: .failed(message: String(localized: "Couldn't save the image. Your verse is safe \u{2014} try again."), retry: 0),
                action: .saveImage
            )
        }
    }

    // MARK: - Capture

    /// Renders the card at 360x640 @3x = an exact 1080x1920 frame.
    private func renderCard() -> UIImage? {
        let card = VerseShareCardView(
            verseText: verseText,
            verseReference: verseReference,
            background: ReadPalette.verseCardBackgrounds[presetIndex],
            photo: photoSelected ? photo : nil
        )
        .frame(width: Dimens.verseCardCanvasWidth, height: Dimens.verseCardCanvasHeight)
        let renderer = ImageRenderer(content: card)
        renderer.scale = Dimens.verseCardExportPixelRatio
        return renderer.uiImage
    }

    private func captureCardToFile() -> URL? {
        guard let image = renderCard(), let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(exportFileName)_\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private var exportFileName: String {
        let allowed = CharacterSet.alphanumerics
        var slug = ""
        var lastWasSeparator = false
        for scalar in verseReference.unicodeScalars {
            if allowed.contains(scalar) && scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                slug += "_"
                lastWasSeparator = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty { return "Hallelujah" }
        return "Hallelujah_" + String(slug.prefix(40))
    }
}

// MARK: - Preset backgrounds

extension ReadPalette {
    /// `ColorTheme.verseCardBackgrounds` — one colour is a flat fill, two a
    /// diagonal gradient.
    static var verseCardBackgrounds: [[Color]] {
        [
            [Color(readRGB: 0x0D0D0D)],
            [Color(readRGB: 0x4B1716)],
            [Color(readRGB: 0x2E1F4B)],
            [Color(readRGB: 0x1C3325)],
            [Color(readRGB: 0x16244A)],
            [Color(readRGB: 0x1A2552), Color(readRGB: 0x3A2A5C)],
        ]
    }

    /// `ColorTheme.verseCardPhotoSwatch`.
    static var verseCardPhotoSwatch: [Color] {
        [Color(readRGB: 0xE8A05A), Color(readRGB: 0x8A4A5E), Color(readRGB: 0x2A2350)]
    }
}

/// `verseCardDecoration`: flat colour or top-left→bottom-right gradient.
private struct VerseCardBackground: View {
    let colors: [Color]

    var body: some View {
        if colors.count == 1, let first = colors.first {
            first
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Card

/// `VerseShareCard` — the shareable card at its design size (300 wide,
/// 16:9 portrait) scaled 1.2x onto the 360x640 canvas.
struct VerseShareCardView: View {
    let verseText: String
    let verseReference: String
    let background: [Color]
    let photo: UIImage?

    private static let designHeight: CGFloat = Dimens.verseCardDesignWidth * 16.0 / 9.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            VerseCardBackground(colors: background)

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Dimens.verseCardDesignWidth, height: Self.designHeight)
                    .clipped()
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(26.0 / 255.0), location: 0),
                        .init(color: Color.black.opacity(102.0 / 255.0), location: 0.45),
                        .init(color: Color.black.opacity(235.0 / 255.0), location: 0.72),
                        .init(color: Color.black.opacity(245.0 / 255.0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(spacing: 0) {
                VerseBlock(
                    verseText: verseText.trimmingCharacters(in: .whitespacesAndNewlines),
                    verseReference: verseReference.uppercased(),
                    overPhoto: photo != nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(EdgeInsets(
                top: Dimens.verseCardPaddingTop,
                leading: Dimens.verseCardPaddingH,
                bottom: Dimens.verseCardPaddingBottom,
                trailing: Dimens.verseCardPaddingH
            ))
        }
        .frame(width: Dimens.verseCardDesignWidth, height: Self.designHeight)
        .clipped()
        .scaleEffect(
            Dimens.verseCardCanvasWidth / Dimens.verseCardDesignWidth,
            anchor: .topLeading
        )
        .frame(
            width: Dimens.verseCardCanvasWidth,
            height: Dimens.verseCardCanvasHeight,
            alignment: .topLeading
        )
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: Dimens.verseCardLogoSize, height: Dimens.verseCardLogoSize)
            Spacer().frame(width: Dimens.spacing8)
            Text("Hallelujah".uppercased())
                .font(.custom(Typography.fontFamily, size: Dimens.verseCardBrandFontSize, relativeTo: .body).weight(.semibold))
                .tracking(2)
                .foregroundStyle(ReadPalette.white)
            Spacer(minLength: 0)
            Text("hallelujah.today")
                .font(.custom(Typography.fontFamily, size: Dimens.verseCardDomainFontSize, relativeTo: .body))
                .foregroundStyle(ReadPalette.white45)
        }
    }
}

/// Accent rule, verse and reference, centred in the space above the footer.
/// The verse starts at a size chosen by word count and shrinks to fit
/// (floor `verseCardFontSizeMin`), never truncating.
private struct VerseBlock: View {
    let verseText: String
    let verseReference: String
    let overPhoto: Bool

    private var preferredFontSize: CGFloat {
        let words = verseText.split(whereSeparator: { $0.isWhitespace }).count
        let few = Dimens.verseCardFewWords
        let typicalMin = Dimens.verseCardTypicalMinWords
        let typicalMax = Dimens.verseCardTypicalMaxWords
        let long = Dimens.verseCardLongWords
        let w = CGFloat(words)
        if w <= few { return Dimens.verseCardFontSizeFewWords }
        if w >= long { return Dimens.verseCardFontSizeLong }
        if w < typicalMin {
            return lerp(w, few, typicalMin, Dimens.verseCardFontSizeFewWords, Dimens.verseCardFontSizeTypical)
        }
        if w <= typicalMax { return Dimens.verseCardFontSizeTypical }
        return lerp(w, typicalMax, long, Dimens.verseCardFontSizeTypical, Dimens.verseCardFontSizeLong)
    }

    private func lerp(_ value: CGFloat, _ fromWords: CGFloat, _ toWords: CGFloat, _ fromSize: CGFloat, _ toSize: CGFloat) -> CGFloat {
        let t = (value - fromWords) / (toWords - fromWords)
        return (fromSize + (toSize - fromSize) * t).rounded()
    }

    var body: some View {
        GeometryReader { proxy in
            let size = preferredFontSize
            // Reference line (10pt, ~12pt tall) + accent + gaps.
            let reserved = Dimens.verseCardAccentHeight + Dimens.verseCardAccentGap + Dimens.verseCardReferenceGap + 14
            let available = max(proxy.size.height - reserved, 20)
            let leading = size > Dimens.verseCardFontSizeTypical ? 1.25 : 1.45

            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(ReadPalette.verseShareGold)
                    .frame(width: Dimens.verseCardAccentWidth, height: Dimens.verseCardAccentHeight)
                Spacer().frame(height: Dimens.verseCardAccentGap)
                Text(verseText)
                    .font(.system(size: size, weight: .regular, design: .serif))
                    .lineSpacing(size * (leading - 1.2))
                    .minimumScaleFactor(Dimens.verseCardFontSizeMin / size)
                    .foregroundStyle(ReadPalette.white)
                    .shadow(color: overPhoto ? Color.black.opacity(0.4) : Color.clear, radius: 6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: available, alignment: .topLeading)
                Spacer().frame(height: Dimens.verseCardReferenceGap)
                Text(verseReference)
                    .font(.custom(Typography.fontFamily, size: Dimens.verseCardReferenceFontSize, relativeTo: .body).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(ReadPalette.verseShareGold)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
    }
}

// MARK: - Controls

private struct VerseSwatch<Art: View>: View {
    let selected: Bool
    let label: LocalizedStringKey
    let action: () -> Void
    let art: Art

    init(selected: Bool, label: LocalizedStringKey, action: @escaping () -> Void, @ViewBuilder art: () -> Art) {
        self.selected = selected
        self.label = label
        self.action = action
        self.art = art()
    }

    var body: some View {
        Button(action: action) {
            art
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(ReadPalette.white10, lineWidth: 1))
                .padding(selected ? Dimens.spacing4 : 0)
                .frame(width: Dimens.verseShareSwatchSize, height: Dimens.verseShareSwatchSize)
                .overlay(
                    Circle().strokeBorder(
                        selected ? ReadPalette.verseShareGold : Color.clear,
                        lineWidth: Dimens.spacing2
                    )
                )
                .animation(.easeInOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

private struct PhotoSwatchArt: View {
    let photo: UIImage?

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                ReadPalette.black.opacity(0.35)
            } else {
                LinearGradient(colors: ReadPalette.verseCardPhotoSwatch, startPoint: .top, endPoint: .bottom)
            }
            Image(systemName: "photo")
                .font(.system(size: Dimens.iconSizeSmall))
                .foregroundStyle(ReadPalette.white)
        }
    }
}

private struct VersePhotoChip: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Dimens.spacing6) {
                Image(systemName: systemName)
                    .font(.system(size: Dimens.iconSizeSmall - 2))
                    .foregroundStyle(ReadPalette.white)
                Text(label)
                    .readText(Typography.labelMedium)
            }
            .padding(.horizontal, Dimens.spacing12)
            .padding(.vertical, Dimens.spacing8)
            .background(Capsule().fill(ReadPalette.verseShareTileFill))
            .overlay(Capsule().strokeBorder(ReadPalette.verseShareTileBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// `VerseShareNotice` — inline result of the last action.
private struct VerseShareNotice: View {
    let failed: Bool
    let message: String
    let detail: String?
    let actionLabel: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: failed ? "exclamationmark.triangle" : "checkmark")
                .font(.system(size: Dimens.iconSizeSmall - 2, weight: .semibold))
                .foregroundStyle(failed ? ReadPalette.verseShareFailedIcon : ReadPalette.verseShareGold)
            Spacer().frame(width: Dimens.spacing8)
            VStack(alignment: .leading, spacing: Dimens.spacing2) {
                Text(message)
                    .readText(Typography.labelMedium)
                    .lineSpacing(12 * 0.35)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .typography(Typography.labelSmall)
                        .tracking(0.5)
                        .foregroundStyle(ReadPalette.white45)
                }
            }
            .padding(.vertical, Dimens.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .readText(Typography.labelLarge, weight: .semibold, color: ReadPalette.verseShareGold)
                        .padding(.horizontal, Dimens.spacing8)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Dimens.spacing12)
        .padding(.vertical, Dimens.spacing4)
        .frame(minHeight: Dimens.verseShareSecondaryMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .fill(failed ? ReadPalette.verseShareFailedFill : ReadPalette.verseShareSavedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(failed ? ReadPalette.verseShareFailedBorder : ReadPalette.verseShareSavedBorder, lineWidth: 1)
        )
    }
}

/// `VerseShareButton` — `primary` is the gold call to action, otherwise a dark
/// tile. `hint` is the one-line caption saying what the action produces.
struct VerseShareButton: View {
    let primary: Bool
    let systemName: String?
    let label: LocalizedStringKey
    let hint: LocalizedStringKey?
    let busy: Bool
    let busyLabel: LocalizedStringKey?
    let enabled: Bool
    let action: () -> Void

    private var foreground: Color {
        primary ? ReadPalette.verseShareOnGold : ReadPalette.white
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Dimens.spacing2) {
                HStack(spacing: Dimens.spacing8) {
                    if busy {
                        ReadSpinner(size: Dimens.iconSizeSmall, color: foreground)
                    } else if let systemName {
                        Image(systemName: systemName)
                            .font(.system(size: Dimens.iconSizeSmall - 2, weight: .semibold))
                            .foregroundStyle(foreground)
                    }
                    Text(busy ? (busyLabel ?? label) : label)
                        .readText(
                            primary ? Typography.titleSmall : Typography.labelMedium,
                            weight: .semibold,
                            color: foreground
                        )
                        .multilineTextAlignment(.center)
                }
                if let hint, !busy {
                    Text(hint)
                        .typography(Typography.labelSmall)
                        .tracking(0)
                        .foregroundStyle(foreground.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Dimens.spacing12)
            .padding(.vertical, Dimens.spacing8)
            .frame(
                maxWidth: .infinity,
                minHeight: primary ? Dimens.verseSharePrimaryMinHeight : Dimens.verseShareSecondaryMinHeight,
                maxHeight: primary ? nil : CGFloat.infinity
            )
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                    .fill(primary ? ReadPalette.verseShareGold : ReadPalette.verseShareTileFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(primary ? Color.clear : ReadPalette.verseShareTileBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled || busy ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }
}

/// `PhotoAccessSheet` (`lib/sheets/share/photo_access_sheet.dart`).
private struct VersePhotoAccessSheet: View {
    let onOpenSettings: () -> Void
    let onUseColour: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadDragHandle(margin: Dimens.spacing12, width: Dimens.spacing40, color: ReadPalette.white24)

            Spacer().frame(height: Dimens.spacing8)

            Image(systemName: "photo")
                .font(.system(size: Dimens.iconSize))
                .foregroundStyle(ReadPalette.verseShareGold)
                .padding(Dimens.spacing8)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(ReadPalette.verseShareGold.opacity(0.12))
                )

            Spacer().frame(height: Dimens.spacing16)

            Text("Allow access to your photos")
                .font(.system(size: Dimens.verseSharePhotoSheetTitleFontSize, weight: .semibold, design: .serif))
                .foregroundStyle(ReadPalette.white)

            Spacer().frame(height: Dimens.spacing8)

            Text("Hallelujah needs photo access to use your own picture behind a verse, and to save finished cards to your gallery. We only touch the picture you choose \u{2014} nothing else.")
                .typography(Typography.bodySmall)
                .lineSpacing(12 * 0.55)
                .foregroundStyle(ReadPalette.white60)

            Spacer().frame(height: Dimens.spacing20)

            VerseShareButton(
                primary: true,
                systemName: "gearshape",
                label: "Open Settings",
                hint: nil,
                busy: false,
                busyLabel: nil,
                enabled: true,
                action: onOpenSettings
            )

            Spacer().frame(height: Dimens.spacing8)

            VerseShareButton(
                primary: false,
                systemName: nil,
                label: "Not now \u{2014} use a colour",
                hint: nil,
                busy: false,
                busyLabel: nil,
                enabled: true,
                action: onUseColour
            )
        }
        .padding(EdgeInsets(top: 0, leading: Dimens.spacing20, bottom: Dimens.spacing16, trailing: Dimens.spacing20))
    }
}

// MARK: - Activity sheet

struct ActivityItems: Identifiable {
    let id = UUID()
    let values: [Any]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// Runs once the system share sheet is done, whatever the user did
    /// (shared, copied, cancelled).
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let onComplete = onComplete
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onComplete?() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
