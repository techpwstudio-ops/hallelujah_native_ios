import SwiftUI

/// Ported from `TermsAndPrivacyText`
/// (`lib/widgets/authentication/terms_and_privacy_text.dart`): one line of
/// body-small text with "Terms of Service"/"Privacy Policy" as bold, tappable
/// links. Dart opens them in a custom tab (`openCustomTab`); `AttributedString`
/// `.link` runs give the same "tap opens the URL" behavior for free via
/// SwiftUI's built-in link handling — no `UITextContentType`/gesture-recognizer
/// wiring needed.
struct TermsAndPrivacyTextView: View {
    private let configuration = AppConfiguration.current

    var body: some View {
        Text(attributedText)
            .typography(Typography.bodySmall)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .tint(.white)
    }

    private var attributedText: AttributedString {
        var result = AttributedString("By continuing, you agree to our ")

        var terms = AttributedString("Terms of Service")
        terms.link = configuration.termsAndConditionsURL
        terms.font = Font.custom(Typography.fontFamily, size: Typography.bodySmall.size).weight(.bold)

        let and = AttributedString(" and ")

        var privacy = AttributedString("Privacy Policy")
        privacy.link = configuration.privacyPolicyURL
        privacy.font = Font.custom(Typography.fontFamily, size: Typography.bodySmall.size).weight(.bold)

        let dot = AttributedString(".")

        result += terms
        result += and
        result += privacy
        result += dot
        return result
    }
}
