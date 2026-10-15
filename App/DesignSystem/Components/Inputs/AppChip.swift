import SwiftUI

/// Ported from `SongTypeTopNavigationButton`
/// (`lib/widgets/home/song_type_top_nav_button.dart`), generalized into a
/// reusable selectable pill rather than the song-type-specific one Dart has:
/// same 36pt height, same radius (`Radius.md`, matching Dart's literal `8`),
/// same selected/unselected color inversion (selected = bold-ink fill with
/// inverse label, same `textPrimary`/`textInverse` pair `AppButton`'s primary
/// variant and `AppToggle`'s on-state use — one consistent "selected/active"
/// language across the whole component set). Unselected fill is
/// `surfacePrimary`, which is also the numeric match for Dart's `fillColor`
/// literal here (see `OTPField.swift`'s note on why that token, not
/// `surfaceInput`, is the right one outside actual text-entry surfaces).
///
/// No loading state: Dart's own chip has none — it is an inert selection
/// toggle, never the target of an async action — so none is invented here
/// either.
struct AppChip: View {
    let title: String
    var isSelected: Bool = false
    var enabled: Bool = true
    /// When true, the pill's own background stretches to fill whatever
    /// width its parent proposes. `Text` has no internal
    /// `.frame(maxWidth: .infinity)` of its own, so wrapping a plain
    /// `AppChip(...)` in `.frame(maxWidth: .infinity)` at a call site only
    /// grows the invisible tap-target box, not the visible fill — this
    /// flag is what T42's full-width Music/Episode toggle pair needs
    /// (`SongTypeTopNavigationButton` wrapped in `Expanded` in Dart). Every
    /// existing call site omits it and keeps hugging its content.
    var stretches: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let height: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Text(L10n.tr(title))
                .typography(Typography.labelLarge)
                .foregroundStyle(isSelected ? theme.color(.textInverse) : theme.color(.textPrimary))
                .padding(.horizontal, Spacing.sm)
                .frame(maxWidth: stretches ? .infinity : nil)
                .frame(height: Self.height)
        }
        .buttonStyle(.plain)
        .modifier(AppChipSurface(isSelected: isSelected, selectedFill: theme.color(.textPrimary)))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .animation(MotionCurve.fast, value: isSelected)
    }
}

/// Selected keeps the solid ink fill (Flutter); unselected is interactive glass.
private struct AppChipSurface: ViewModifier {
    let isSelected: Bool
    let selectedFill: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(selectedFill)
            }
        } else {
            content.glassRounded(Radius.md, interactive: true)
        }
    }
}
