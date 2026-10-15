import SwiftUI

/// Flutter `ColorTheme` / `Colors.*` literals the Search, Library, UserPlaylists
/// and CreatorProfile screens spell directly (`lib/theme/colors.dart`) which
/// have no semantic token in `ColorToken`. D12: exact parity, so these are the
/// Dart values 1:1 (kept next to the screens that use them rather than
/// editing the shared token files).
enum ParityColor {
    /// `Colors.white.withOpacity(0.6)` — `ColorTheme.white60`.
    static let white60 = Color.white.opacity(0.6)
    /// `ColorTheme.white70`.
    static let white70 = Color.white.opacity(0.7)
    /// `Colors.grey` (`ColorTheme.grey`) — 0xFF9E9E9E.
    static let grey = Color(red: 158 / 255, green: 158 / 255, blue: 158 / 255)
    /// `Colors.grey.shade400` — `ColorTheme.greySubtle`.
    static let greySubtle = Color(red: 189 / 255, green: 189 / 255, blue: 189 / 255)
    /// `Colors.grey.shade600` — `ColorTheme.greyMuted`.
    static let greyMuted = Color(red: 117 / 255, green: 117 / 255, blue: 117 / 255)
    /// `Colors.grey.shade800` — `ColorTheme.greyDark`.
    static let greyDark = Color(red: 66 / 255, green: 66 / 255, blue: 66 / 255)
    /// `Colors.grey.shade900` — `ColorTheme.greyDeep`.
    static let greyDeep = Color(red: 33 / 255, green: 33 / 255, blue: 33 / 255)
    /// `fillColor` / `ColorTheme.fillColor` — 0xFF1D1D1D.
    static let fill = Color(red: 29 / 255, green: 29 / 255, blue: 29 / 255)
    /// `ColorTheme.darkFillColor` — 0xFF282828.
    static let darkFill = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    /// `ColorTheme.darkSurface` — 0xFF1C1C1C.
    static let darkSurface = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    /// `ColorTheme.searchBarColor` — 0xFF333333.
    static let searchBar = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    /// `ColorTheme.darkGold` — 0xFFB8861B.
    static let darkGold = Color(red: 184 / 255, green: 134 / 255, blue: 27 / 255)
    /// velocity_x `Vx.yellow400` (Material yellow 400) — now-playing accent.
    static let yellow400 = Color(red: 1.0, green: 238 / 255, blue: 88 / 255)
    /// `ColorTheme.containerBorderColor` — 0x33BBBBBB.
    static let containerBorder = Color(red: 187 / 255, green: 187 / 255, blue: 187 / 255).opacity(0.2)
    /// `ColorTheme.bottomSheetBgColor` — 0xFF111111.
    static let sheetBackground = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
}

/// Text styles the Flutter rows build with `textTheme.X.copyWith(fontWeight:)`.
enum ParityText {
    /// `titleSmall` with `fontWeight: w500` (every search/list row title).
    static let rowTitle = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1.4)
    /// Same, `w700` (now-playing row).
    static let rowTitleActive = TypographyToken(size: 14, weight: .bold, lineHeightMultiple: 1.4)
    /// `bodySmall` (row subtitles).
    static let rowSubtitle = Typography.bodySmall
    /// `bodyMedium` w500 (end message, "See all" is bodySmall w500).
    static let bodyMediumMedium = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1.5)
    static let bodySmallMedium = TypographyToken(size: 12, weight: .medium, lineHeightMultiple: 1.5)
    /// `appBarTextStyle` — `titleLarge` w600.
    static let appBar = Typography.titleLarge
}

/// `dotSign` (`lib/constants/strings.dart`).
let parityDotSign = " \u{2022} "

extension String {
    /// velocity_x `String.capitalized`: first character upper-cased, the rest
    /// lower-cased (NOT per-word like Foundation's `capitalized`).
    var parityCapitalized: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst().lowercased()
    }
}

/// The 3-line tile every Flutter list row shares (`SongSearchItem`,
/// `CreatorSearchItem`, `UserPlaylistListItem`, library rows): 16pt horizontal
/// and 6pt vertical padding, 12pt gap, title `titleSmall` w500 white, 3pt gap,
/// subtitle `bodySmall` white60.
struct ParityRowText: View {
    let title: String
    var subtitle: String?
    var isActive = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .typography(isActive ? ParityText.rowTitleActive : ParityText.rowTitle)
                .foregroundStyle(isActive ? ParityColor.yellow400 : Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
            if let subtitle {
                Spacer().frame(height: 3)
                Text(subtitle)
                    .typography(ParityText.rowSubtitle)
                    .foregroundStyle(isActive ? ParityColor.yellow400.opacity(0.8) : ParityColor.white60)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// `IconButton(close_rounded, white60, size 18, 32x32 compact)`.
struct ParityCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ParityColor.white60)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}

/// `IconButton(more_vert, white60, size 20, 32x32 compact)`.
struct ParityMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 20))
                .foregroundStyle(ParityColor.white60)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }
}

/// `_buildEmptyState` / `_buildMinCharsHint` (`content_search_page.dart`): a
/// 56pt grey icon in a `greyDeep` 16pt-radius tile (20pt padding), 24pt gap,
/// `titleLarge` white, 8pt gap, `bodyMedium` greySubtle (height 1.5).
struct ParityEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(ParityColor.greyMuted)
                .padding(Dimens.spacing20)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                        .fill(ParityColor.greyDeep)
                )
            Spacer().frame(height: Dimens.spacing24)
            Text(title)
                .typography(Typography.titleLarge)
                .foregroundStyle(Color.white)
            Spacer().frame(height: Dimens.spacing8)
            Text(message)
                .typography(Typography.bodyMedium)
                .foregroundStyle(ParityColor.greySubtle)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Dimens.paddingExtraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `ShimmerItem` (`lib/widgets/search_shimmer.dart`): 48pt thumb, 18pt title
/// bar, 16pt subtitle bar 40% screen width, 8pt spacing, 4pt radius, 16/8
/// padding, base 1D1D1D on 282828 highlight.
struct ParityShimmerItem: View {
    var body: some View {
        HStack(spacing: Dimens.spacing8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ParityColor.fill)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: Dimens.spacing8 / 1.5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ParityColor.fill)
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ParityColor.fill)
                    .frame(width: 160, height: 16)
            }
        }
        .padding(.horizontal, Dimens.spacing16)
        .padding(.vertical, Dimens.spacing8)
    }
}

/// `SearchShimmer`: 8 `ShimmerItem`s separated by 14pt, one shimmer pass.
struct ParityShimmerList: View {
    var count = 8

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { _ in ParityShimmerItem() }
        }
        .shimmer()
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// `SearchWidgetUi` (`lib/widgets/navigation/search_widget_ui.dart`): the
/// tap-through fake bar on Search and Library. 8pt outer padding, 1D1D1D fill
/// radius 8 with a same-colour 1pt border, 8pt inner padding, a 20pt search
/// icon (8pt padded), "Search" in `bodyMedium` grey @ 0.7 (4pt padded) —
/// 70pt natural height. The caller supplies the page's own horizontal inset
/// (Dart: `Dimens.screenPaddingAll` = 8), so the bar sits 16pt from the edge.
struct ParityFakeSearchBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .padding(Dimens.spacing8)
                Text("Search")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(ParityColor.grey.opacity(0.7))
                    .padding(Dimens.spacing4)
                Spacer(minLength: 0)
            }
            .padding(Dimens.spacing8)
            .glassRounded(Dimens.cornerRadius, interactive: true)
            .padding(Dimens.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }
}

/// `SongTypeTopNavigationButton` (`lib/widgets/home/song_type_top_nav_button.dart`):
/// 36pt tall, radius 8, selected = white fill + black label, otherwise
/// `fillColor` + white label; label 14pt w500, 8pt horizontal padding.
struct ParityTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private static let label = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1)

    var body: some View {
        Button(action: action) {
            Text(title)
                .typography(Self.label)
                .foregroundStyle(Color.white)
                .padding(.horizontal, Dimens.spacing8)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                .glassRounded(8, isSelected ? .tinted(.brandPrimary) : .regular, interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension ParityColor {
    /// velocity_x `Vx.yellow500` — now-playing title in `BaseMediaListTile`.
    static let yellow500 = Color(red: 1.0, green: 235 / 255, blue: 59 / 255)
    /// `Colors.white54` / `Colors.white70` / `Colors.white60` (Material alphas).
    static let white54 = Color.white.opacity(0.54)
}

/// `Formater.formatDurationText` (`lib/utils/formater.dart`).
func parityDurationText(_ duration: Int?) -> String {
    guard let duration, duration > 0 else { return "0 min" }
    let hours = duration / 3600
    let minutes = (duration % 3600) / 60
    let seconds = duration % 60
    if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
    if minutes > 0 { return "\(minutes) min" }
    return "\(seconds) sec"
}

/// `Formater.formatToDate` -> `dd/MM/yyyy`.
func parityDateText(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter.string(from: date)
}

/// Material `Checkbox` with the app theme (`checkboxTheme` white fill):
/// 18pt box, radius 2; checked = white with a black tick, unchecked = a 2pt
/// white 70% outline; inside the 48pt minimum tap target.
struct ParityCheckbox: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isChecked ? Color.white : Color.clear)
                .frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(isChecked ? Color.white : ParityColor.white70, lineWidth: 2)
                .frame(width: 18, height: 18)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
    }
}

/// `ContinueToAddPlaylist` / `_CompactContinueButton`: a pill with "Continue"
/// + arrow, `#1D1D1D` fill, gold (`#FFE7A3`) 1pt border with a soft glow when
/// active, `#282828` / white24 border when disabled; text `labelLarge` w600
/// in `#FFC857` (white60 when disabled).
struct ParityContinueButton: View {
    var isDisabled = false
    let action: () -> Void

    private static let gold = Color(red: 1.0, green: 0xC8 / 255, blue: 0x57 / 255)
    private static let goldBorder = Color(red: 1.0, green: 0xE7 / 255, blue: 0xA3 / 255)
    private static let label = TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1, tracking: 0.1)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Continue")
                    .typography(Self.label)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isDisabled ? ParityColor.white60 : Self.gold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isDisabled ? ParityColor.darkFill : ParityColor.fill)
                    .shadow(color: isDisabled ? Color.clear : Self.goldBorder.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .overlay(Capsule().stroke(isDisabled ? Color.white.opacity(0.24) : Self.goldBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
