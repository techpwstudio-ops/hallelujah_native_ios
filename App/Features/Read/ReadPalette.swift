import SwiftUI

/// D12 — exact Flutter colours for the Read tab and Verse of the Day, taken
/// from `lib/theme/colors.dart` (`ColorTheme`, `bookHighlightColors`). The
/// Flutter app is dark-only (`themeMode: ThemeMode.dark`), so these are fixed
/// values rather than light/dark asset-catalog tokens. Computed properties
/// (not stored statics) so there is no Swift 6 global-state concern.
enum ReadPalette {
    static var white: Color { Color(readRGB: 0xFFFFFF) }
    static var black: Color { Color(readRGB: 0x000000) }
    static var white10: Color { Color(readRGB: 0xFFFFFF, opacity: 0.10) }
    static var white24: Color { Color(readRGB: 0xFFFFFF, opacity: 0.24) }
    static var white45: Color { Color(readRGB: 0xFFFFFF, opacity: 0.45) }
    static var white60: Color { Color(readRGB: 0xFFFFFF, opacity: 0.60) }
    static var white70: Color { Color(readRGB: 0xFFFFFF, opacity: 0.70) }
    /// `ColorTheme.secondaryTextColor` — white at 70%.
    static var secondaryText: Color { Color(readRGB: 0xFFFFFF, opacity: 0.70) }
    /// `ColorTheme.tertiaryTextColor` — white at 47%.
    static var tertiaryText: Color { Color(readRGB: 0xFFFFFF, opacity: 0.47) }

    /// `backgroundColor` / `ColorTheme.dark`.
    static var background: Color { Color(readRGB: 0x000000) }
    /// `ColorTheme.fillColor`.
    static var fill: Color { Color(readRGB: 0x1D1D1D) }
    /// `ColorTheme.bottomSheetBgColor`.
    static var sheetBackground: Color { Color(readRGB: 0x111111) }
    /// `ColorTheme.chapterNumberBoxBgColor`.
    static var chapterBox: Color { Color(readRGB: 0x212121) }
    /// `ColorTheme.darkFillColor`.
    static var darkFill: Color { Color(readRGB: 0x282828) }
    /// `ColorTheme.searchBarColor`.
    static var searchBar: Color { Color(readRGB: 0x333333) }
    /// `ColorTheme.darkSurface`.
    static var darkSurface: Color { Color(readRGB: 0x1C1C1C) }
    /// `ColorTheme.lyricsBorderColor`.
    static var lyricsBorder: Color { Color(readRGB: 0x2A2A2A) }
    /// `ColorTheme.logoColor` (cursor colour, search highlight tint).
    static var logo: Color { Color(readRGB: 0xB07514) }
    /// `ColorTheme.darkGold` (verse focus highlight).
    static var darkGold: Color { Color(readRGB: 0xB8861B) }
    /// `ColorTheme.hintColor`.
    static var hint: Color { Color(readRGB: 0x808080) }
    /// `Colors.grey`.
    static var grey: Color { Color(readRGB: 0x9E9E9E) }
    /// `ColorTheme.greySubtle` (`grey.shade400`).
    static var greySubtle: Color { Color(readRGB: 0xBDBDBD) }
    /// `ColorTheme.greyMuted` (`grey.shade600`).
    static var greyMuted: Color { Color(readRGB: 0x757575) }
    /// `ColorTheme.dragHandlerColor`.
    static var dragHandle: Color { Color(readRGB: 0xD9D9D9) }
    /// `ColorTheme.commentInputBorderColor` (0x80B4BBC6).
    static var commentInputBorder: Color { Color(readRGB: 0xB4BBC6, opacity: 128.0 / 255.0) }
    /// `ColorTheme.containerBorderColor` (0x33BBBBBB).
    static var containerBorder: Color { Color(readRGB: 0xBBBBBB, opacity: 51.0 / 255.0) }
    /// `Divider()` colour in the dark Material 3 theme (outlineVariant).
    static var divider: Color { Color(readRGB: 0x49454F) }

    /// `bookHighlightColors`, as the hex strings stored on a highlight.
    static let highlightHexes: [String] = ["#FFABAB", "#FFDDAB", "#ABFFCD", "#BCABFF"]

    // MARK: Verse share (ColorTheme.verseShare*)

    static var verseShareGold: Color { Color(readRGB: 0xC9A55C) }
    static var verseShareOnGold: Color { Color(readRGB: 0x1A1408) }
    static var verseShareTileFill: Color { Color(readRGB: 0x151515) }
    static var verseShareTileBorder: Color { Color(readRGB: 0x262626) }
    static var verseShareSavedFill: Color { Color(readRGB: 0x17140C) }
    static var verseShareSavedBorder: Color { Color(readRGB: 0x4A3E22) }
    static var verseShareFailedFill: Color { Color(readRGB: 0x2A1212) }
    static var verseShareFailedBorder: Color { Color(readRGB: 0x5C2626) }
    static var verseShareFailedIcon: Color { Color(readRGB: 0xE5736B) }
}

extension Color {
    /// 0xRRGGBB literal helper. Named `readRGB` so it can never collide with a
    /// design-system initializer another feature adds later.
    init(readRGB rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Parses `#RRGGBB` / `RRGGBB` (a stored highlight's `colorHex`).
    init?(readHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(readRGB: rgb)
    }
}

extension View {
    /// A `TypographyToken` (Flutter `AppTextStyles.*`) with an optional weight
    /// override — Flutter call sites spell `copyWith(fontWeight: …)` all over.
    func readText(_ token: TypographyToken, weight: Font.Weight? = nil, color: Color = ReadPalette.white) -> some View {
        typography(token)
            .fontWeight(weight ?? token.weight)
            .foregroundStyle(color)
    }
}

/// `DragHandler` (`lib/widgets/drag_handler.dart`): 80x2, #D9D9D9, 2pt radius,
/// 16pt vertical margin.
struct ReadDragHandle: View {
    var margin: CGFloat = 16
    var width: CGFloat = Dimens.dragHandlerWidth
    var color: Color = ReadPalette.dragHandle

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: Dimens.dragHandlerHeight)
            .padding(.vertical, margin)
            .frame(maxWidth: .infinity)
    }
}

/// Hosts a sheet's content the way `showAppSheet` does: flat #111111 surface
/// (`ColorTheme.bottomSheetBgColor`), no system drag indicator, and the dock
/// hide/show bookkeeping `AppSheetContainer` does for shared sheets.
struct ReadSheetContainer<Content: View>: View {
    private let content: Content

    @Environment(AppNavigationCoordinator.self) private var coordinator: AppNavigationCoordinator?

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ReadPalette.sheetBackground.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear { coordinator?.sheetPresented() }
            .onDisappear { coordinator?.sheetDismissed() }
    }
}

extension View {
    func readSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        detents: Set<PresentationDetent> = [.large],
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ReadSheetContainer(content: content)
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(cornerRadius)
                .presentationBackground(ReadPalette.sheetBackground)
        }
    }

    func readSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        detents: Set<PresentationDetent> = [.large],
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            ReadSheetContainer { content(value) }
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(cornerRadius)
                .presentationBackground(ReadPalette.sheetBackground)
        }
    }
}

/// Flutter `Empty` (`lib/widgets/empty.dart`): centred, w600 default-size
/// text, 16pt padding.
struct ReadEmptyText: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.semibold))
            .foregroundStyle(ReadPalette.white)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity)
    }
}

/// Flutter `ProgressSpinner` (`loading_indicator` circleStrokeSpin, white,
/// 32x32): a rotating white arc.
struct ReadSpinner: View {
    var size: CGFloat = 32
    var color: Color = ReadPalette.white

    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: max(size / 12, 2), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
