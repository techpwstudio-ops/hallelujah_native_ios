import SwiftUI

/// Ports `FAQPage` (`lib/views/support/faqs.dart`): an `ExpansionTile` per
/// FAQ inside a `RefreshIndicator`, backed by the `faqProvider` Riverpod
/// watches there and `FAQViewModel` fetches through here instead. Mirrors
/// `SectionDetailView`'s own ScrollView-plus-`.refreshable` shape for a
/// `LoadState`-driven screen, for consistency with this app's other
/// network-backed screens.
struct FAQView: View {
    @State private var viewModel = FAQViewModel()

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            content
                .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .navigationTitle("FAQ")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .failed:
            failedState
        case .empty:
            EmptyStateView(title: "No FAQs available")
        case .loaded(let faqs):
            faqList(faqs)
        }
    }

    /// `Icons.wifi_off` (`faqs.dart`'s `error` branch) — kept as a bespoke
    /// state, rather than reusing `ErrorStateView` (which hardcodes its own
    /// `.warning` glyph), so this can show that exact icon and copy.
    /// `IconToken.noNetwork` already maps to this SF Symbol ("wifi.slash"),
    /// so no raw `Image(systemName:)` is needed.
    private var failedState: some View {
        VStack(spacing: Spacing.md) {
            theme.icon(.noNetwork)
                .font(.system(size: 40))
                .foregroundStyle(theme.color(.textSecondary))
            Text("Failed to load FAQs")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
            AppButton.ghost("Retry", width: nil) {
                Task { await viewModel.refresh() }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// One `DisclosureGroup` per FAQ, `ForEach`-keyed by `FAQItem.id`
    /// (`Identifiable`) rather than index, unlike Dart's `ListView.separated`
    /// — see `FAQItem`'s own doc comment for why the two differ here.
    private func faqList(_ faqs: [FAQItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(faqs) { faq in
                DisclosureGroup {
                    Text(faq.answer)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.xs)
                } label: {
                    Text(faq.question)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }
}
