import SwiftUI

extension View {
    /// The navigation bar of a pushed page.
    ///
    /// Flutter's `AppBar` is solid black, so below iOS 26 the bar is forced to
    /// `color` (visible, or hidden while `isVisible` is false — the collapsing
    /// heroes). On iOS 26 the system draws it instead: the back / action
    /// buttons become Liquid Glass and the page scrolls under a soft
    /// scroll-edge effect, over the same black page — natural there, and still
    /// black at rest. Hidden stays hidden on every OS.
    @ViewBuilder
    func appNavigationBarBackground(_ color: Color = .black, isVisible: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(isVisible ? .automatic : .hidden, for: .navigationBar)
        } else {
            self
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(isVisible ? .visible : .hidden, for: .navigationBar)
        }
    }
}
