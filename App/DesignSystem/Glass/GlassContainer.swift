import SwiftUI

/// Groups adjacent `GlassSurface`s so that, on iOS 26+, they can visually
/// merge/morph via the real `GlassEffectContainer` (e.g. a mini player pill
/// and a nearby control that should read as one sheet of glass when close).
/// Below iOS 26 there is no equivalent merging mechanic for the material
/// fallback, so this is a plain passthrough there — grouping is purely a
/// real-Liquid-Glass capability, not something the fallback recipe can fake.
struct GlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = Spacing.sm, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
