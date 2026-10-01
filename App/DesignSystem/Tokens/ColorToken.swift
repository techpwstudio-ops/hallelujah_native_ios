import SwiftUI

/// Semantic color tokens backing `Assets.xcassets/Colors` (24 sets, scaffolded
/// before this task — see `progress.md` "Already on disk"). Every case name
/// matches its color set name exactly; the set's containing "Colors" group has
/// `provides-namespace: false`, so the asset name has no folder prefix.
enum ColorToken: String, CaseIterable, Sendable {
    case backgroundPrimary
    case backgroundSecondary
    case backgroundElevated
    case surfacePrimary
    case surfaceSecondary
    case surfaceInput
    case textPrimary
    case textSecondary
    case textTertiary
    case textInverse
    case textOnBrand
    case brandPrimary
    case brandSecondary
    case brandTint
    case border
    case separator
    case glassTint
    case glassStroke
    case glassHighlight
    case overlayScrim
    case statusSuccess
    case statusWarning
    case statusError
    case statusInfo

    var color: Color {
        Color(rawValue, bundle: .main)
    }
}
