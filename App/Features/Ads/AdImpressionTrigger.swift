import SwiftUI

/// `AdImpressionTrigger` (`lib/ads/ad_visibility.dart`): fires `onVisible`
/// once, after the creative has stayed on screen for `minDuration`
/// (500ms). An impression means "a human saw this", never "we fetched it", so
/// wrap every ad creative in this and call `AdsRepository.trackImpression`
/// from `onVisible`.
///
/// SwiftUI has no visible-fraction callback, so presence in the view tree
/// (`onAppear`/`onDisappear` — lazy containers only build what is near the
/// viewport) stands in for Flutter's 50%-visible rule; the dwell timer is
/// the same.
struct AdImpressionTrigger<Content: View>: View {
    var minDuration: Duration = .milliseconds(500)
    let onVisible: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dwell: Task<Void, Never>?
    @State private var fired = false

    var body: some View {
        content()
            .onAppear {
                guard !fired, dwell == nil else { return }
                dwell = Task {
                    try? await Task.sleep(for: minDuration)
                    guard !Task.isCancelled else { return }
                    fired = true
                    dwell = nil
                    onVisible()
                }
            }
            .onDisappear {
                dwell?.cancel()
                dwell = nil
            }
    }
}
