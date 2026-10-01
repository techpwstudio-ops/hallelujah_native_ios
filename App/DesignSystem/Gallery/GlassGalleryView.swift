import SwiftUI

/// Every `GlassSurface` variant over a busy, scrolling backdrop — the
/// surface a blur/material recipe actually has to prove itself against (T11's
/// Done criterion: "one preview shows every variant over a scrolling photo
/// background at 120 fps"). No photo asset exists yet in the catalog, so a
/// generated gradient field stands in for one; swapping in a real photo is a
/// one-line change once artwork loading exists (T13).
struct GlassGalleryView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                scrollingBackdrop
                VStack(spacing: Spacing.lg) {
                    regularCard
                    clearCard
                    tintedCard
                    interactivePill
                    groupedContainer
                }
                .padding(Spacing.lg)
                .padding(.top, 240) // start below the backdrop's opening band so it's visible behind the first card
            }
        }
        .background(theme.color(.backgroundPrimary))
    }

    private var scrollingBackdrop: some View {
        LinearGradient(
            colors: [
                ColorToken.brandTint.color,
                ColorToken.brandPrimary.color,
                ColorToken.statusInfo.color,
                ColorToken.brandSecondary.color,
                ColorToken.statusError.color,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 1400)
    }

    private var regularCard: some View {
        GlassSurface(.regular, cornerRadius: Radius.lg) {
            label("Regular", subtitle: "Nav bars, cards, sheets")
        }
    }

    private var clearCard: some View {
        GlassSurface(.clear, cornerRadius: Radius.lg) {
            label("Clear", subtitle: "Large surfaces over media")
        }
    }

    private var tintedCard: some View {
        GlassSurface(.tinted(.brandPrimary), cornerRadius: Radius.lg) {
            label("Tinted", subtitle: "Premium badges, selected states")
        }
    }

    private var interactivePill: some View {
        GlassSurface(.regular, interactive: true) {
            label("Interactive pill", subtitle: "Mini player, tab bar")
                .padding(.horizontal, Spacing.md)
        }
    }

    private var groupedContainer: some View {
        GlassContainer {
            HStack(spacing: Spacing.sm) {
                GlassSurface(.regular, cornerRadius: Radius.full) {
                    theme.icon(.favorite)
                        .foregroundStyle(theme.color(.textInverse))
                        .padding(Spacing.md)
                }
                GlassSurface(.regular, cornerRadius: Radius.full) {
                    theme.icon(.share)
                        .foregroundStyle(theme.color(.textInverse))
                        .padding(Spacing.md)
                }
            }
        }
    }

    private func label(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textInverse))
            Text(subtitle)
                .typography(Typography.bodySmall)
                .foregroundStyle(theme.color(.textInverse).opacity(0.7))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Light") {
    GlassGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    GlassGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}
