import SwiftUI

/// One search result row in `AddSongsToPlaylistView` — genuinely not
/// `CreatorSongRow` wearing a different hat: that component has no
/// selection slot at all (its own doc comment says as much), and this
/// picker's whole point is a per-row selection state, so a trailing
/// checkmark-circle indicator is core to the row, not a bolt-on. Native
/// equivalent of Dart's `AddToPlaylistCheckBox` (a plain `Checkbox` next to
/// each `Song` row in select mode). `IconToken` has no checkmark-circle case
/// to reuse, so this is a literal `Image(systemName:)` instead — the same
/// ad hoc, un-tokenized escape hatch `AccountSetupView.genderOption` already
/// uses for its own selection circle (`largecircle.fill.circle`/`circle`).
/// Same tappable-row idiom as `CreatorSongRow`: `.onTapGesture`, not a
/// `Button`.
struct AddSongsToPlaylistRow: View {
    let song: Song
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(\.appTheme) private var theme

    private static let thumbnailSize: CGFloat = 44

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: song.displayImage,
            variant: .sm,
            allowedVariants: song.displayImageVariants
        )
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ArtworkView(url: resolvedArtwork, width: Self.thumbnailSize, height: Self.thumbnailSize)

            Text(song.title ?? "Untitled")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? theme.color(.brandPrimary) : theme.color(.textTertiary))
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}
