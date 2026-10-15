import SwiftUI
import UIKit

/// Settings → App Language: the language of the app's own text (separate from
/// Content Languages, which choose which songs/Bible the feed shows). Each row
/// is written in its own script so it stays findable whatever the current UI
/// language is; picking one applies immediately (`AppLanguageStore`).
struct AppLanguageView: View {
    private var store: AppLanguageStore { AppLanguageStore.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: Dimens.spacing12) {
                Text("Choose the language used for menus, buttons and messages in the app.")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(AuthColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                ForEach(AppLanguage.allCases) { language in
                    row(language)
                }
            }
            .padding(Dimens.screenPaddingAll * 2)
        }
        .background(AuthColors.background.ignoresSafeArea())
        .navigationTitle("App Language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ language: AppLanguage) -> some View {
        let isSelected = store.selected == language
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.select(language)
        } label: {
            HStack(spacing: Dimens.spacing12) {
                Image(systemName: language == .system ? "iphone" : "character.bubble")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: language.nativeName)
                        .typography(Typography.titleMedium)
                        .foregroundStyle(Color.white)
                    if let english = language.englishName, english != language.nativeName {
                        Text(verbatim: english)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(AuthColors.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.35))
            }
            .padding(Dimens.paddingLarge)
            .frame(maxWidth: .infinity)
            .glassRounded(Dimens.cornerRadiusMedium, isSelected ? .tinted(.brandPrimary) : .regular, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
