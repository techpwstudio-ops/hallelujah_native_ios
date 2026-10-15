import SwiftUI

/// Call-site sugar over `GlassSurface` (the one glass implementation): real
/// Liquid Glass on iOS 26, material fallback below. Wrap sibling glass
/// elements in `GlassContainer` so they blend/morph as the system does.
extension View {
    /// Draws this view on a glass surface of `shape`.
    func glassBackground<S: InsettableShape>(
        _ variant: GlassVariant = .regular,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        GlassSurface(variant, in: shape, interactive: interactive) { self }
    }

    func glassCapsule(_ variant: GlassVariant = .regular, interactive: Bool = false) -> some View {
        glassBackground(variant, in: Capsule(style: .continuous), interactive: interactive)
    }

    func glassCircle(_ variant: GlassVariant = .regular, interactive: Bool = false) -> some View {
        glassBackground(variant, in: Circle(), interactive: interactive)
    }

    func glassRounded(
        _ radius: CGFloat = Radius.lg,
        _ variant: GlassVariant = .regular,
        interactive: Bool = false
    ) -> some View {
        glassBackground(variant, in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }
}

/// A round glass icon button (floating controls over artwork, toolbars).
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 18
    var variant: GlassVariant = .regular
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .glassCircle(variant, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
