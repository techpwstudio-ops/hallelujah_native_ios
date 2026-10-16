import SwiftUI

/// Black launch splash (`FlashScreen`, `lib/views/launch/flash.dart`) with the
/// app logo (`AppLogo`, `app_logo.png`) animating in at its centre.
///
/// Deliberate native addition: the Flutter splash shows no logo animation
/// (`_minSplashDuration` is zero and the OS launch screen carries a static
/// logo), and here the OS launch screen is a plain black fill
/// (`UILaunchScreen` → `LaunchBackground`). So this view starts from black and
/// the logo eases in over it — the black matches, so there's no visible seam.
/// It replaces the Material spinner, which would sit on top of the logo; the
/// breathing glow is the "still loading" cue instead.
///
/// The animation only gets to play because `SplashViewModel.minimumDuration`
/// now holds the splash for about as long as one entrance plus one glow
/// breath; the session check still runs concurrently with that hold.
struct SplashView: View {
    /// 150pt, same as the logo on the Flutter app's launch storyboard.
    private static let logoSize: CGFloat = 150
    /// Sampled from the logo's gold — only used for a faint halo, so not worth
    /// a design-system token.
    private static let glowColor = Color(red: 0.92, green: 0.66, blue: 0.17)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: SplashViewModel
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.85

    init(viewModel: SplashViewModel = SplashViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Self.glowColor.opacity(0.35), Self.glowColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: Self.logoSize * 0.9
                        )
                    )
                    .frame(width: Self.logoSize * 1.8, height: Self.logoSize * 1.8)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)

                Image(decorative: "AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
            }
        }
        .onAppear(perform: playLogoAnimation)
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

    /// Logo springs up from 80% while fading in; the halo then fades in and
    /// breathes for as long as the splash is up. Reduce Motion keeps just the
    /// fade — no scaling or pulsing.
    private func playLogoAnimation() {
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.4)) {
                logoOpacity = 1
                logoScale = 1
            }
            return
        }
        withAnimation(.easeOut(duration: 0.5)) {
            logoOpacity = 1
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 0.8)) {
            glowOpacity = 1
        }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            glowScale = 1.1
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
