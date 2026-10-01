import SwiftUI

/// The single glass implementation for every raised surface in the app (nav
/// bars, tab bar, sheets, mini player, cards, overlays — see the "Glass UI"
/// non-negotiable in `progress.md`). On iOS 26+ it draws real Liquid Glass;
/// below that it falls back to a material + stroke + highlight recipe. Call
/// sites never touch `.ultraThinMaterial` or `#available(iOS 26...)`
/// themselves — this is the one place that split lives.
///
/// **Q1 (iOS 17 floor vs. Liquid Glass), resolved 2026-09-16 — recommendation
/// (a) adopted, and validated against the Flutter app itself**: the Flutter
/// mini player (`lib/widgets/player/music_player_bottom_ios26.dart`) already
/// does exactly this split — it gates real Liquid Glass
/// (`liquid_glass_renderer` package) behind `PlatformInfo.isIOS26OrHigher()`
/// and renders nothing there below iOS 26, relying on a separate non-glass
/// mini player for everyone else. One primitive, two implementations, is not
/// just the safer iOS 17-floor option — it is what the reference app itself
/// ships today.
///
/// The corner treatment for a floating pill (mini player, tab bar) uses
/// `Radius.full` (48pt) to match `LiquidRoundedSuperellipse(borderRadius: 48)`
/// in that same Flutter widget, confirmed from the Dart source rather than
/// guessed.
///
/// The real-Glass API surface below (`Glass.regular`/`.clear`/`.tint(_:)`/
/// `.interactive()`, `View.glassEffect(_:in:)`) is written from the iOS 26
/// SDK as documented at its announcement — there has been no build against
/// an actual iOS 26 SDK to confirm these exact signatures compile. Flag this
/// specifically on the first real build.
struct GlassSurface<S: InsettableShape, Content: View>: View {
    private let variant: GlassVariant
    private let shape: S
    private let isInteractive: Bool
    private let content: Content

    init(
        _ variant: GlassVariant = .regular,
        in shape: S,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.shape = shape
        self.isInteractive = interactive
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(material)
                        shape.fill(tintColor.opacity(tintOpacity))
                    }
                }
                .overlay {
                    shape.strokeBorder(edgeGradient, lineWidth: 1)
                }
                .clipShape(shape)
        }
    }

    // MARK: - iOS 26+ path

    @available(iOS 26.0, *)
    private var glass: Glass {
        let base: Glass
        switch variant {
        case .regular: base = .regular
        case .clear: base = .clear
        case let .tinted(token): base = Glass.regular.tint(token.color)
        }
        return isInteractive ? base.interactive() : base
    }

    // MARK: - Fallback path (material + stroke + highlight)

    /// No Dart precedent pins an exact material weight (Flutter's blur is a
    /// continuous sigma, not SwiftUI's five discrete `Material` steps) — this
    /// mapping is a judgment call: `clear` gets the least blur/opacity so
    /// content behind it stays legible over large areas, `regular`/`tinted`
    /// get one step more substance, matching how they read on iOS 26 glass.
    private var material: Material {
        switch variant {
        case .regular, .tinted: .regularMaterial
        case .clear: .ultraThinMaterial
        }
    }

    private var tintColor: Color {
        switch variant {
        case .regular, .clear: ColorToken.glassTint.color
        case let .tinted(token): token.color
        }
    }

    private var tintOpacity: Double {
        switch variant {
        case .regular: 1 // `glassTint` already carries its own alpha in the asset
        case .clear: 0.6
        case .tinted: 0.22 // a brand/status color is opaque in its own asset — blend it, don't paint over the material
        }
    }

    /// Stroke that fades from `glassHighlight` at the top edge to
    /// `glassStroke` elsewhere, approximating specular light catching the
    /// top of a glass edge — the "stroke + highlight" half of the fallback
    /// recipe's name.
    private var edgeGradient: LinearGradient {
        LinearGradient(
            colors: [ColorToken.glassHighlight.color, ColorToken.glassStroke.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension GlassSurface where S == RoundedRectangle {
    init(
        _ variant: GlassVariant = .regular,
        cornerRadius: CGFloat = Radius.lg,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            variant,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: interactive,
            content: content
        )
    }
}

extension GlassSurface where S == Capsule {
    init(
        _ variant: GlassVariant = .regular,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(variant, in: Capsule(style: .continuous), interactive: interactive, content: content)
    }
}
