import SwiftUI

/// `AppRoute.faqs` — the Help & Support dashboard opened on its FAQ tab.
struct FAQView: View {
    var body: some View { HelpView(initialIndex: 0) }
}

/// Ports `FAQPage` (`lib/views/support/faqs.dart`): `ExpansionTile`s
/// (16/4 tile padding, 16/0/16/16 children padding, white70 -> white arrow)
/// in a pull-to-refresh list, with Flutter's loading / "Failed to load FAQs"
/// (wifi_off, Retry) / "No FAQs available" states.
struct FAQContentView: View {
    @State private var viewModel = FAQViewModel()

    var body: some View {
        content
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(AccountParity.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: UIScreen.main.bounds.height * 0.3)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(AccountParity.white)
                    Spacer().frame(height: 12)
                    Text("Failed to load FAQs")
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.white)
                    Spacer().frame(height: 8)
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text("Retry")
                            .font(AccountParity.font(14, .medium))
                            .foregroundStyle(AccountParity.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .refreshable { await viewModel.refresh() }
        case .empty:
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 200)
                    Text("No FAQs available")
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.white)
                }
                .frame(maxWidth: .infinity)
            }
            .refreshable { await viewModel.refresh() }
        case .loaded(let faqs):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(faqs) { faq in
                        FAQRow(faq: faq)
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}

private struct FAQRow: View {
    let faq: FAQItem
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 16) {
                    Text(faq.question)
                        .font(AccountParity.font(14, .semibold))
                        .lineSpacing(14 * 0.5 - 3)
                        .foregroundStyle(AccountParity.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(expanded ? AccountParity.white : AccountParity.white70)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(faq.answer)
                    .font(AccountParity.font(12))
                    .lineSpacing(6)
                    .foregroundStyle(AccountParity.white60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .clipped()
    }
}
