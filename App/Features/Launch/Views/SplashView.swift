import SwiftUI

/// Matches `FlashScreen.build` (`lib/views/launch/flash.dart`): a black
/// `Scaffold` with a centred Material `CircularProgressIndicator` (36pt,
/// 4pt stroke, `colorScheme.primary` = white in the dark theme). The Flutter
/// splash plays no logo animation (`_minSplashDuration` is zero; the OS launch
/// screen already shows the static logo).
struct SplashView: View {
    @State private var viewModel: SplashViewModel

    init(viewModel: SplashViewModel = SplashViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MaterialSpinner(color: .white)
        }
        .task {
            await viewModel.start()
        }
        .alert(
            "app.update.available.title",
            isPresented: isUpdateAlertPresented
        ) {
            if let url = viewModel.availableUpdate?.trackViewURL {
                Button("app.update.available.action") {
                    UIApplication.shared.open(url)
                }
            }
            Button("app.update.dismiss.action", role: .cancel) {}
        } message: {
            Text("app.update.available.message")
        }
    }

    /// The alert is dismissible and non-blocking, same as Dart's
    /// `UpgradeAlert` wrapping (not gating) the flash route — declining it
    /// just clears `availableUpdate` rather than exiting or re-prompting.
    private var isUpdateAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.availableUpdate != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissAvailableUpdate() }
            }
        )
    }
}

// The background is a fixed literal (`Color.black`, theme-agnostic — see
// above), so unlike most views here a single preview covers both appearances.
#Preview {
    SplashView()
}
