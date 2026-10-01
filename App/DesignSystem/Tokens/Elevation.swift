import SwiftUI

/// One shadow step: radius/vertical offset/opacity for `.shadow(...)`.
struct ElevationToken: Sendable {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
}

/// Shadow scale for raised surfaces. Flutter's theme only defines a single
/// `shadowOpacity` constant (0.06, `lib/theme/values.dart`), no leveled
/// scale — `level1`'s opacity matches that constant exactly; `level2`/`level3`
/// are new, scaled up from it for the glass design system's layering
/// (`GlassSurface`, T11, needs more than one level: cards vs. sheets vs. the
/// expanded player).
enum Elevation {
    static let level0 = ElevationToken(radius: 0, y: 0, opacity: 0)
    static let level1 = ElevationToken(radius: 8, y: 2, opacity: 0.06)
    static let level2 = ElevationToken(radius: 16, y: 6, opacity: 0.10)
    static let level3 = ElevationToken(radius: 24, y: 12, opacity: 0.16)

    static let allCases: [(name: String, token: ElevationToken)] = [
        ("level0", level0),
        ("level1", level1),
        ("level2", level2),
        ("level3", level3),
    ]
}

extension View {
    func elevation(_ token: ElevationToken) -> some View {
        shadow(color: .black.opacity(token.opacity), radius: token.radius, y: token.y)
    }
}
