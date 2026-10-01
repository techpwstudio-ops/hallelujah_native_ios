import SwiftUI

/// Renders T14's two deliverables for visual QA: the `HapticFeedback`
/// vocabulary (a button per case) and a matched-geometry mini-player ->
/// full-player expansion demo. Same preview-only role as the other
/// per-task galleries.
///
/// The expansion demo can't structurally live under `Components/` yet —
/// the real mini/full player screens don't exist until M5 (T34/T35) — so
/// it's wired up directly here, reusing T13's actual `ArtworkView`/
/// `MarqueeText`/`SeekBar`/`LikeButton` (rather than throwaway rectangles)
/// so the morph is proven against production views, with a synthetic
/// `picsum.photos` demo URL standing in for a real song the same way
/// `MediaGalleryView` already does — there's no `Song` model yet to source
/// real artwork from.
///
/// T14's Done criterion ("mini-player -> full-player expansion runs
/// without a dropped frame") is demonstrated structurally: one
/// `@Namespace` shared by both states, `MotionCurve.expand`/`.collapse`
/// driving the transition. It isn't measured — profiling needs an actual
/// build/run, out of scope for this pass per `progress.md`'s standing
/// constraints, the same caveat T13's gallery already documented.
///
/// No custom "shared transition" code is needed for ordinary screen
/// push/pop: `lib/theme/page_transitions.dart` only customizes Android (a
/// 300ms custom builder); its iOS branch uses
/// `CupertinoPageTransitionsBuilder` unmodified, which is exactly what
/// SwiftUI's `NavigationStack` already does natively. There's nothing to
/// port there, so this file has no "screen transition" section — only the
/// two things that actually needed new code.
struct MotionGalleryView: View {
    @Environment(\.appTheme) private var theme
    @Namespace private var playerNamespace
    @State private var isExpanded = false

    private static let demoArtworkURL = URL(string: "https://picsum.photos/seed/motion-demo/400")

    private static let hapticDemos: [(name: String, haptic: HapticFeedback)] = [
        ("Selection", .selection),
        ("Impact — light", .impact(.light)),
        ("Impact — medium (Dart's mediumImpact)", .mediumImpact),
        ("Impact — heavy", .impact(.heavy)),
        ("Impact — soft", .impact(.soft)),
        ("Impact — rigid", .impact(.rigid)),
        ("Notification — success", .notification(.success)),
        ("Notification — warning", .notification(.warning)),
        ("Notification — error", .notification(.error)),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hapticsSection
                    expansionSection
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xxl * 2) // clears the pinned mini player
            }
            .background(theme.color(.backgroundPrimary))

            if !isExpanded {
                miniPlayerDemo
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .overlay {
            if isExpanded {
                fullPlayerDemo
            }
        }
    }

    // MARK: - Haptics

    private var hapticsSection: some View {
        section("Haptics") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.hapticDemos, id: \.name) { demo in
                    AppButton.ghost(demo.name, action: { demo.haptic.trigger() })
                }
            }
        }
    }

    // MARK: - Matched-geometry expansion

    private var expansionSection: some View {
        section("Matched-geometry player expansion") {
            Text("Tap the mini player pinned to the bottom of this screen — its artwork, title, and background all morph into the full-player layout below using one shared @Namespace. Tap the close button on the full player to collapse it back.")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
        }
    }

    private var miniPlayerDemo: some View {
        GlassSurface(.regular, cornerRadius: Radius.full) {
            HStack(spacing: Spacing.sm) {
                ArtworkView(url: Self.demoArtworkURL, width: 44, height: 44, cornerRadius: Radius.sm)
                    .matchedGeometryEffect(id: "artwork", in: playerNamespace)
                MarqueeText(text: "Matched Geometry Demo Track")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .matchedGeometryEffect(id: "title", in: playerNamespace)
                theme.icon(.play)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(.textPrimary))
            }
            .padding(.horizontal, Spacing.sm)
            .frame(height: 56)
        }
        .matchedGeometryEffect(id: "background", in: playerNamespace)
        .contentShape(RoundedRectangle(cornerRadius: Radius.full, style: .continuous))
        .onTapGesture {
            HapticFeedback.selection.trigger()
            withAnimation(MotionCurve.expand) { isExpanded = true }
        }
    }

    private var fullPlayerDemo: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                Spacer()
                Button {
                    HapticFeedback.selection.trigger()
                    withAnimation(MotionCurve.collapse) { isExpanded = false }
                } label: {
                    theme.icon(.close)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.color(.textPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Spacing.lg)

            ArtworkView(url: Self.demoArtworkURL, width: 280, height: 280, cornerRadius: Radius.lg)
                .matchedGeometryEffect(id: "artwork", in: playerNamespace)

            VStack(spacing: Spacing.xs) {
                MarqueeText(text: "Matched Geometry Demo Track")
                    .frame(width: 240)
                    .matchedGeometryEffect(id: "title", in: playerNamespace)
                Text("Demo Artist")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
            }

            Spacer()

            SeekBar(position: 62, duration: 214, buffered: 140) { _ in }
                .padding(.horizontal, Spacing.lg)

            LikeButton(isLiked: true) {}
                .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(theme.color(.backgroundPrimary))
                .matchedGeometryEffect(id: "background", in: playerNamespace)
        )
        .ignoresSafeArea()
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
    MotionGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MotionGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}
