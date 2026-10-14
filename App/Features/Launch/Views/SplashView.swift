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

/// Approximation of Material's indeterminate `CircularProgressIndicator`
/// (36pt box, 4pt round-less stroke): a rotating arc whose sweep grows and
/// shrinks, driven by one repeating animation.
struct MaterialSpinner: View {
    var color: Color = .white
    var size: CGFloat = 36
    var lineWidth: CGFloat = 4

    @State private var spinning = false
    @State private var sweeping = false

    var body: some View {
        Circle()
            .trim(from: 0, to: sweeping ? 0.75 : 0.05)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .frame(width: size - lineWidth, height: size - lineWidth)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(.linear(duration: 1.333).repeatForever(autoreverses: false)) {
                    spinning = true
                }
                withAnimation(.easeInOut(duration: 0.666).repeatForever(autoreverses: true)) {
                    sweeping = true
                }
            }
    }
}
