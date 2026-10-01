import SwiftUI

/// Renders every T12 core component for visual QA, including each one's
/// loading and disabled state where it has one (T12's Done criterion:
/// "component gallery preview; each has a loading and disabled state").
/// Preview-only, not part of any real screen — same role as
/// `TokenGalleryView`/`GlassGalleryView` for T10/T11.
///
/// A thin wrapper around `ComponentGalleryContent` rather than a single
/// struct: `.toastOverlay()` injects `\.toastCenter` into the environment
/// of the view it's attached to, which only reaches views *below* it in the
/// tree. A view can't read via `@Environment` a value it sets on itself in
/// its own `body` — the same reason real screens are expected to sit below
/// wherever `.toastOverlay()` is applied once near the app root, rather than
/// pairing the modifier and the read in one view.
struct ComponentGalleryView: View {
    var body: some View {
        ComponentGalleryContent()
            .toastOverlay()
    }
}

private struct ComponentGalleryContent: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    @State private var textFieldValue = ""
    @State private var secureFieldValue = "hunter2"
    @State private var otpCode = ""
    @State private var otpErrorCode = "12"
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var selectedChip = 0
    @State private var isSheetPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                buttonsSection
                textFieldsSection
                otpSection
                togglesSection
                chipsSection
                sheetSection
                shimmerSection
                stateViewsSection
                toastSection
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        section("Buttons") {
            VStack(spacing: Spacing.sm) {
                AppButton(label: "Primary", action: {})
                AppButton(label: "Primary — loading", action: {}, isLoading: true)
                AppButton(label: "Primary — disabled", action: {}, enabled: false)
                AppButton.secondary("Secondary", action: {})
                AppButton.secondary("Secondary — loading", isLoading: true, action: {})
                AppButton.secondary("Secondary — disabled", enabled: false, action: {})
                AppButton.ghost("Ghost", leadingIcon: .retry, action: {})
                AppButton.ghost("Ghost — disabled", enabled: false, action: {})
            }
        }
    }

    // MARK: - Text fields

    private var textFieldsSection: some View {
        section("Text fields") {
            VStack(spacing: Spacing.sm) {
                AppTextField(text: $textFieldValue, label: "Email", placeholder: "you@example.com", keyboardType: .emailAddress, textContentType: .emailAddress)
                AppTextField(text: $secureFieldValue, label: "Password", isSecure: true)
                AppTextField(text: .constant(""), label: "Disabled", placeholder: "Can't edit this", enabled: false)
                AppTextField(text: .constant("bad@value"), label: "With error", errorMessage: "That email is already in use")
            }
        }
    }

    // MARK: - OTP

    private var otpSection: some View {
        section("OTP field") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                OTPField(code: $otpCode)
                OTPField(code: $otpErrorCode, hasError: true)
                OTPField(code: .constant("123"), enabled: false)
            }
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        section("Toggles") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                AppToggle(isOn: $toggleOn, label: "Notifications")
                AppToggle(isOn: $toggleOff, label: "Explicit content")
                AppToggle(isOn: .constant(true), label: "Disabled — on", enabled: false)
                AppToggle(isOn: .constant(false), label: "Disabled — off", enabled: false)
            }
        }
    }

    // MARK: - Chips

    private var chipsSection: some View {
        section("Chips") {
            HStack(spacing: Spacing.sm) {
                ForEach(0..<3) { index in
                    AppChip(title: "Chip \(index + 1)", isSelected: selectedChip == index) {
                        selectedChip = index
                    }
                }
                AppChip(title: "Disabled", enabled: false) {}
            }
        }
    }

    // MARK: - Sheet

    private var sheetSection: some View {
        section("Sheet") {
            AppButton.secondary("Present sheet") { isSheetPresented = true }
                .appSheet(isPresented: $isSheetPresented) {
                    VStack(spacing: Spacing.md) {
                        Text("Sheet content")
                            .typography(Typography.titleMedium)
                            .foregroundStyle(theme.color(.textInverse))
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
        }
    }

    // MARK: - Shimmer

    private var shimmerSection: some View {
        section("Shimmer") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonBox(width: 160, height: 16)
                SkeletonBox(width: 220, height: 16)
                SkeletonBox(width: 120, height: 120, radius: Radius.md)
            }
            .shimmer()
        }
    }

    // MARK: - State views

    private var stateViewsSection: some View {
        section("Empty / error / loading states") {
            VStack(spacing: Spacing.lg) {
                EmptyStateView(icon: .favorite, title: "No favorites yet", message: "Songs you like will show up here.", actionTitle: "Browse songs") {}
                ErrorStateView(title: "Something went wrong", message: "Check your connection and try again.") {}
                LoadingStateView(message: "Loading…")
            }
        }
    }

    // MARK: - Toast

    private var toastSection: some View {
        section("Toast") {
            AppButton.secondary("Show toast") {
                toastCenter.show("This is a toast message")
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
    ComponentGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ComponentGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}
