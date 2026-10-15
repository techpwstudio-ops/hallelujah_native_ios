import SwiftUI

/// One tappable row of the song menu (`SheetMenuItem`,
/// `lib/widgets/song/sheet_menu_item.dart`): leading icon, title, optional
/// trailing badge.
struct SongMenuRow<Trailing: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: Self.iconSize))
                    .frame(width: 40, alignment: .leading)
                    .foregroundStyle(theme.color(.textPrimary))
                Text(title)
                    .typography(Self.titleToken)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer(minLength: 0)
                trailing()
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static var iconSize: CGFloat { 20 }
    /// `titleMedium` w500 (`SheetMenuItem`).
    private static let titleToken = TypographyToken(size: 16, weight: .medium, lineHeightMultiple: 1.4)
}

extension SongMenuRow where Trailing == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(systemImage: systemImage, title: title, action: action) { EmptyView() }
    }
}

/// `GoPremiumLogo` — the badge shown on premium-only rows for free listeners.
struct GoPremiumBadge: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("Premium")
            .typography(Typography.labelSmall)
            .foregroundStyle(theme.color(.textOnBrand))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(theme.color(.brandPrimary), in: Capsule())
    }
}
