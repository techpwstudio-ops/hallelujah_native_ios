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
        var result = AttributedString(localized: "By continuing, you agree to our **Terms of Service** and **Privacy Policy**.")
        let links = [configuration.termsAndConditionsURL, configuration.privacyPolicyURL]
        let boldRanges = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true else { return nil }
            return run.range
        }
        for (index, range) in boldRanges.enumerated() where index < links.count {
            result[range].link = links[index]
            result[range].font = Font.custom(Typography.fontFamily, size: Typography.bodySmall.size).weight(.bold)
        }
        return result
    }
}
