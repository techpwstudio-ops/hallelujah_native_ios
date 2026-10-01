import SwiftUI

/// Pixel-matches `FlashScreen` (`lib/views/launch/flash.dart`) per D10 — no
/// layout changes, only internal implementation differences are allowed.
///
/// Flutter drives both the opacity and scale off one 2-second
/// `AnimationController`, with each animation given an `Interval` sub-range
/// of that timeline that it eases across, then holds its end value for the
/// remainder (`Interval.transformInternal`, verified against the Flutter SDK
/// source: before `begin` the value is 0, after `end` it's clamped to 1).
/// Two independent SwiftUI animations starting at the same instant, each
/// running for its own shorter duration, reproduce that exactly:
/// - opacity: `Interval(0.0, 0.4, Curves.easeIn)` on a 2s controller -> 0.8s
/// - scale: `Interval(0.0, 0.6, Curves.easeOutBack)` on a 2s controller -> 1.2s
///
/// Curve control points verified against the real Flutter SDK source
/// (`curves.dart`): `Curves.easeIn = Cubic(0.42, 0.0, 1.0, 1.0)`,
/// `Curves.easeOutBack = Cubic(0.175, 0.885, 0.32, 1.275)` — both map
/// directly onto `Animation.timingCurve(_:_:_:_:duration:)`'s 4-point cubic
/// Bezier, including `easeOutBack`'s overshoot past 1.0 (its second control
/// point's y is 1.275), so the logo briefly overshoots past full scale
/// exactly as it does in the Flutter build.
struct SplashView: View {
    @State private var viewModel: SplashViewModel
    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.7

    private static let opacityAnimation = Animation.timingCurve(0.42, 0.0, 1.0, 1.0, duration: 0.8)
    private static let scaleAnimation = Animation.timingCurve(0.175, 0.885, 0.32, 1.275, duration: 1.2)

    init(viewModel: SplashViewModel = SplashViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            // `Colors.black` (`lib/theme/colors.dart`) — a fixed literal in
            // Dart, deliberately not the app's themed `backgroundPrimary`
            // token (which would answer light mode differently); the splash
            // is black regardless of theme in the Flutter build too.
            Color.black.ignoresSafeArea()

            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .task {
            withAnimation(Self.opacityAnimation) { logoOpacity = 1 }
            withAnimation(Self.scaleAnimation) { logoScale = 1.0 }
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
