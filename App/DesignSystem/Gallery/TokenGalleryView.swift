import SwiftUI

/// Renders every design token for visual QA — colors, type scale, spacing,
/// radii, elevation, motion durations, and the icon vocabulary. Preview-only;
/// not part of any real screen (T10's Done criterion: "a token gallery
/// preview renders every token in light and dark").
struct TokenGalleryView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                colorSection
                typographySection
                spacingSection
                radiusSection
                elevationSection
                motionSection
                iconSection
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private var colorSection: some View {
        section("Colors") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: Spacing.sm) {
                ForEach(ColorToken.allCases, id: \.self) { token in
                    VStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(token.color)
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(theme.color(.border), lineWidth: 1)
                            )
                        Text(token.rawValue)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textSecondary))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var typographySection: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Typography.allCases, id: \.name) { entry in
                    Text(entry.name)
                        .typography(entry.token)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            }
        }
    }

    private var spacingSection: some View {
        section("Spacing") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Spacing.allCases, id: \.name) { entry in
                    HStack {
                        Text(entry.name)
                            .typography(Typography.labelMedium)
                            .foregroundStyle(theme.color(.textSecondary))
                            .frame(width: 48, alignment: .leading)
                        Rectangle()
                            .fill(theme.color(.brandPrimary))
                            .frame(width: entry.value, height: 12)
                    }
                }
            }
        }
    }

    private var radiusSection: some View {
        section("Radius") {
            HStack(spacing: Spacing.md) {
                ForEach(Radius.allCases, id: \.name) { entry in
                    VStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: entry.value)
                            .fill(theme.color(.surfacePrimary))
                            .frame(width: 56, height: 56)
                        Text(entry.name)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textSecondary))
                    }
                }
            }
        }
    }

    private var elevationSection: some View {
        section("Elevation") {
            HStack(spacing: Spacing.lg) {
                ForEach(Elevation.allCases, id: \.name) { entry in
                    VStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(theme.color(.surfacePrimary))
                            .frame(width: 56, height: 56)
                            .elevation(entry.token)
                        Text(entry.name)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textSecondary))
                    }
                }
            }
            .padding(.top, Spacing.md)
        }
    }

    private var motionSection: some View {
        section("Motion") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(MotionDuration.allCases, id: \.name) { entry in
                    Text("\(entry.name): \(Int(entry.value * 1000)) ms")
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                }
            }
        }
    }

    private var iconSection: some View {
        section("Icons") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: Spacing.md) {
                ForEach(IconToken.allCases, id: \.self) { token in
                    VStack(spacing: Spacing.xs) {
                        theme.icon(token)
                            .foregroundStyle(theme.color(.textPrimary))
                        Text(token.systemName)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textTertiary))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            content()
        }
    }
}

#Preview("Light") {
    TokenGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TokenGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}
