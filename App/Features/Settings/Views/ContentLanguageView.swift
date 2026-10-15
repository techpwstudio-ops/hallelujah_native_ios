import SwiftUI

/// Ports `ContentLanguagePage` (`lib/widgets/authentication/
/// content_language_page.dart`) as Settings opens it (`canPop: true`): dark
/// scaffold titled with the route's label, the rule banner, the two-column
/// language grid, and a full-width "Save" bar that stays inert (dimmed) until
/// the selection — or which language leads it — differs from what loaded.
///
/// Reuses the signup step's `LanguageViewModel`/`RuleBannerView`/
/// `LanguageGridView`, so the two screens can't drift. The primary is the
/// first language picked, as in the signup step.
struct ContentLanguageView: View {
    let label: String
    let canPop: Bool

    @State private var viewModel = LanguageViewModel()
    @State private var initialSelection: [String] = []
    @State private var didLoad = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    private var isChanged: Bool { didLoad && viewModel.selectedLanguages != initialSelection }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AuthColors.background.ignoresSafeArea())
        .parityNavTitle(label)
        .task {
            await viewModel.initialize()
            initialSelection = viewModel.selectedLanguages
            didLoad = true
        }
        .toastOverlay()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            MaterialSpinner(color: .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage {
            Text(message)
                .typography(Typography.bodyMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Dimens.spacing12) {
                        RuleBannerView()
                        LanguageGridView(
                            languageOptions: viewModel.languageOptions,
                            isSelected: viewModel.isSelected,
                            isPrimary: viewModel.isPrimary,
                            canToggle: viewModel.canToggle,
                            onTap: toggle
                        )
                    }
                    .padding(.horizontal, Dimens.screenPaddingAll)
                }
                saveBar
            }
            .padding(Dimens.screenPaddingAll)
        }
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            Text("Save")
                .typography(Typography.titleSmall)
                .fontWeight(.semibold)
                .foregroundStyle(isChanged ? Color.black : Color.white.opacity(0.38))
                .frame(maxWidth: .infinity)
                .frame(height: Dimens.buttonHeight)
                .background {
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(isChanged ? Color.white : AuthColors.fill)
                        .overlay {
                            RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                                .strokeBorder(isChanged ? Color.white : AuthColors.white12, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isChanged || viewModel.saveState == .loading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func toggle(_ name: String) {
        guard !viewModel.toggleLanguage(name) else { return }
        toastCenter.show("You can select up to \(LanguageViewModel.maxSelectableLanguages) languages. Remove one to add another.")
    }

    private func save() async {
        guard await viewModel.saveLanguages() else {
            if case let .error(message) = viewModel.saveState { toastCenter.show(message) }
            return
        }
        initialSelection = viewModel.selectedLanguages
        if canPop { coordinator.pop() }
    }
}
