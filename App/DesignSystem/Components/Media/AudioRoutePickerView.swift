import AVKit
import SwiftUI

/// T35 — the "output picker" line in the roadmap. A full-repo grep of the
/// Flutter reference app found no AirPlay/output-route widget anywhere
/// (`car_play_service.dart`'s `allowAirPlay` is an unrelated
/// text-to-speech `AVAudioSession` category flag, not a UI control) — there
/// is no Dart source to port here at all. Rather than stub an icon that
/// does nothing, this wraps `AVRoutePickerView` directly: a complete,
/// self-contained system control that needs no backend or app state to be
/// genuinely functional today. T39 (Audio output and AirPlay) may add
/// richer in-app output-device UI around it later, but nothing here is
/// half-built in the meantime.
struct AudioRoutePickerView: UIViewRepresentable {
    var tintColor: UIColor
    var activeTintColor: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}
