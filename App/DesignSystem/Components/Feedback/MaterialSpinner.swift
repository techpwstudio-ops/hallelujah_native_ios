import SwiftUI

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

/// `Loader.instance`'s look (`lib/services/loading_service.dart`):
/// `showDialog(barrierDismissible: false)` + `ProgressSpinner(40)` —
/// Material's default barrier is black at 54%. Covers the whole screen and
/// swallows taps while shown.
struct BlockingSpinnerOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.54).ignoresSafeArea()
            MaterialSpinner(color: .white, size: 40, lineWidth: 3)
        }
        .contentShape(Rectangle())
        .transition(.identity)
    }
}
