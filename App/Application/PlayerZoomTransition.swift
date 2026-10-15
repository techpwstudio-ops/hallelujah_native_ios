import SwiftUI

/// The mini-player -> full-player zoom is iOS 18+; iOS 17 falls back to the
/// default full-screen presentation.
extension View {
    @ViewBuilder
    func playerZoomSource(id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func playerZoomTransition(sourceID: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
