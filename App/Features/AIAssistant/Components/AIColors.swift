import SwiftUI

/// Literal colours and fonts from the Flutter AI screens (`lib/theme/colors.dart`,
/// `lib/views/ai/**`). The Flutter AI area is fixed-dark and not theme reactive,
/// so these are file-independent literals rather than `ColorToken`s (D12).
enum AIColors {
    private static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// `backgroundColor` (`Colors.black`).
    static let background = Color.black
    /// `fillColor` / `ColorTheme.fillColor`.
    static let fill = rgb(0x1D1D1D)
    /// `ColorTheme.darkFillColor`.
    static let darkFill = rgb(0x282828)
    /// `ColorTheme.darkGold`.
    static let gold = rgb(0xFFFFFF)
    /// The real `ColorTheme.darkGold` (0xFFB8861B), for the places that must
    /// stay gold as in Flutter (user bubble, suggestion stars) while `gold`
    /// above is white.
    static let darkGold = rgb(0xB8861B)
    /// `ColorTheme.hintColor`.
    static let hint = rgb(0x808080)
    /// `ColorTheme.errorBgColor`.
    static let errorBackground = rgb(0x7F0000)
    /// `Colors.white70` / `ColorTheme.white70`.
    static let white70 = Color.white.opacity(0.7)
    static let white54 = Color.white.opacity(0.54)
    static let white38 = Color.white.opacity(0.38)
    static let white24 = Color.white.opacity(0.24)
    static let white12 = Color.white.opacity(0.12)
    /// Second stop of the "Emet" gradient text (`Color(0xFF999999)`).
    static let gradientGrey = rgb(0x999999)
    /// `Colors.amber.shade200` (inline code).
    static let amber200 = rgb(0xFFE082)
    /// `Colors.redAccent`.
    static let redAccent = rgb(0xFF5252)
    /// `Colors.red.shade400`.
    static let red400 = rgb(0xEF5350)

    /// `TextStyle(fontFamily: fontFamily, fontSize:, fontWeight:)`.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom(Typography.fontFamily, size: size).weight(weight)
    }
}

/// White -> grey gradient text used for "Emet" / "Ask. Seek. Discover.".
struct AIGradientText: View {
    let text: String
    let font: Font
    var vertical: Bool = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white, AIColors.gradientGrey],
                    startPoint: vertical ? .top : .leading,
                    endPoint: vertical ? .bottom : .trailing
                )
            )
    }
}

/// Flutter's `CircularProgressIndicator(strokeWidth: 2, color: ...)` stand-in.
struct AISpinner: View {
    var tint: Color = AIColors.white38
    var size: CGFloat = 20

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(tint)
            .frame(width: size, height: size)
    }
}
