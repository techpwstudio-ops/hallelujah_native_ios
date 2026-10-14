import SwiftUI
import UIKit

/// `VoiceSearchButton` (`lib/widgets/search/voice_search_button.dart`): a mic
/// for a search field. Grey `mic` idle; white `mic.fill` with a breathing,
/// level-reactive halo while listening. Hands the caller only text.
struct VoiceSearchButton: View {
    /// Every recognised phrase, partials included.
    let onResult: (String, Bool) -> Void
    var onListeningChanged: ((Bool) -> Void)?
    var size: CGFloat = 24

    @State private var controller = VoiceSearchController()
    @State private var breathing = false
    @State private var showPermissionAlert = false
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: controller.isListening ? .light : .medium).impactOccurred()
            Task { await controller.toggle() }
        } label: {
            icon
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controller.isListening ? "Stop listening" : "Search by voice")
        .onAppear {
            controller.onResult = onResult
            controller.onListeningChanged = { listening in
                breathing = listening
                onListeningChanged?(listening)
            }
        }
        .onDisappear { controller.cancel() }
        .onChange(of: controller.failure) { _, failure in
            guard let failure else { return }
            switch failure {
            case .permissionDenied: showPermissionAlert = true
            case .unavailable: toastCenter.show("Voice search isn't available on this device")
            case .notHeard: toastCenter.show("Didn't catch that. Tap the mic and try again.")
            case .failed: toastCenter.show("Voice search couldn't start. Please try again.")
            }
        }
        .alert("Microphone access", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone access in Settings to search by voice.")
        }
    }

    @ViewBuilder
    private var icon: some View {
        if controller.isListening {
            let halo = size + Dimens.spacing12
            let breath = breathing ? 1.0 : 0.7
            let amplitude = min(max((breath + controller.level) / 2, 0), 1)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14 + amplitude * 0.18))
                    .frame(width: halo * (0.62 + amplitude * 0.38), height: halo * (0.62 + amplitude * 0.38))
                Image(systemName: "mic.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color.white)
            }
            .frame(width: halo, height: halo)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: breathing)
        } else {
            Image(systemName: "mic")
                .font(.system(size: size))
                .foregroundStyle(ParityColor.grey)
        }
    }
}
