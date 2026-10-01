import SwiftUI

/// Ports `_LibraryItem` (`lib/widgets/creator/library_item_ui.dart`): a
/// leading icon tile, bold title, and a raw count subtitle. Dart draws each
/// icon from a brand SVG (`downloads.svg`/`liked_musics.svg`/
/// `liked_episode.svg`/`liked_artists.svg`) inside an 8pt-rounded thumbnail —
/// ported here as an `IconToken` glyph on a tinted rounded square, the same
/// placeholder-icon posture `IconToken`'s own header comment establishes for
/// every other brand-SVG case.
struct LibraryQuickLinkRow: View {
    let icon: IconToken
    let title: String
    let count: Int
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let iconBoxSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(theme.color(.surfaceSecondary))
                    .frame(width: Self.iconBoxSize, height: Self.iconBoxSize)
                    .overlay {
                        theme.icon(icon)
                            .font(.system(size: 18))
                            .foregroundStyle(theme.color(.textPrimary))
                    }

                Text(title)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(count)")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))

                theme.icon(.chevronForward)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}
