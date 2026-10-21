import SwiftUI
import UIKit

/// Width-driven layout for every window shape the app runs in: iPhone, iPad
/// (full screen, Split View, Slide Over, Stage Manager), foldables, and a Mac
/// running the iPad build in a freely resizable window.
///
/// The Flutter app has no tablet layouts, so D12 parity is defined at phone
/// width: every rule here hands back the phone value unchanged at or below
/// `phoneMaxWidth` and only diverges above it. Breakpoints follow the live
/// width of the window the view sits in — never the device idiom, the size
/// class or `UIScreen` — so a window that is resized, rotated, split or
/// unfolded mid-session re-lays out on the spot.
enum AdaptiveLayout {
    /// The widest iPhone in portrait (Pro Max / Plus). At or below this a
    /// screen is laid out exactly as Flutter lays it out.
    static let phoneMaxWidth: CGFloat = 440
    /// Text, forms, settings and chat: roughly 75 characters of body text.
    static let readableWidth: CGFloat = 640
    /// One column of media-led content (the player in portrait, artwork
    /// headers, share cards).
    static let mediaColumnWidth: CGFloat = 560
    /// Single-purpose forms (sign in, OTP, account setup).
    static let formWidth: CGFloat = 480
    /// The floating mini player pill and its ad strip.
    static let dockMaxWidth: CGFloat = 600
    /// From this width a landscape window puts the player's artwork and its
    /// details side by side instead of stacking them.
    static let sideBySideMinWidth: CGFloat = 840
    /// The smallest window a Mac may shrink the app to: one iPhone screen.
    static let macMinimumWindowSize = CGSize(width: 390, height: 640)

    /// Wider than any phone: tablets, unfolded foldables, Mac windows.
    static func isWide(_ width: CGFloat) -> Bool {
        width > phoneMaxWidth
    }

    /// Landscape and wide enough to place two columns side by side.
    static func isSideBySide(_ size: CGSize) -> Bool {
        size.width >= sideBySideMinWidth && size.width > size.height
    }

    /// Column count for a grid that shows `phone` columns on a phone: one more
    /// column for every `minItemWidth` of width beyond that, never fewer than
    /// the phone count.
    static func columns(phone: Int, minItemWidth: CGFloat, in width: CGFloat) -> Int {
        guard isWide(width), minItemWidth > 0 else { return phone }
        return max(phone, Int(width / minItemWidth))
    }

    /// The width a phone-proportional size (`width * 0.8`, `width - 32`, a
    /// square sized to the screen) should be computed from: the real width on
    /// a phone, held at `cap` above it so it stops growing with the window.
    static func proportionalWidth(_ width: CGFloat, cap: CGFloat = mediaColumnWidth) -> CGFloat {
        min(width, max(cap, phoneMaxWidth))
    }
}

private struct LayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Width of the window, or of the sheet, the view lives in. `0` until it
    /// has been measured (and in previews), which reads as a phone.
    var layoutWidth: CGFloat {
        get { self[LayoutWidthKey.self] }
        set { self[LayoutWidthKey.self] = newValue }
    }
}

/// Publishes this view's own width as `layoutWidth` to everything inside it.
private struct LayoutWidthReader: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.layoutWidth, width)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Holds content to a centred column once the window is wider than a phone.
/// At phone width both frames are all-`nil`, which leaves layout untouched.
private struct ReadableWidth: ViewModifier {
    @Environment(\.layoutWidth) private var layoutWidth
    let maxWidth: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        let isConstrained = AdaptiveLayout.isWide(layoutWidth)
        content
            .frame(maxWidth: isConstrained ? maxWidth : nil, alignment: alignment)
            .frame(maxWidth: isConstrained ? CGFloat.infinity : nil)
    }
}

extension View {
    /// Measures this view's width and publishes it as `layoutWidth`. Applied
    /// once at the window root and again at the root of every sheet, whose
    /// width on iPad and Mac is not the window's.
    func measuresLayoutWidth() -> some View {
        modifier(LayoutWidthReader())
    }

    /// Caps content at `maxWidth`, centred, on a tablet, foldable or Mac
    /// window; a no-op on a phone. Put it on the content *inside* a scroll
    /// view so the scroll view itself (its gestures and indicator) still
    /// spans the whole window.
    func readableContentWidth(
        _ maxWidth: CGFloat = AdaptiveLayout.readableWidth,
        alignment: Alignment = .center
    ) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth, alignment: alignment))
    }
}

/// Mac-only window rules for the iPad build ("Designed for iPad"): keeps the
/// window from being dragged smaller than one phone screen, below which no
/// layout is designed. iPhone and iPad manage their own window sizes.
enum MacWindowSizing {
    @MainActor
    static func apply() {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = AdaptiveLayout.macMinimumWindowSize
        }
    }
}
