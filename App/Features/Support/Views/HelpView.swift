import SwiftUI

/// Ports `HelpSupportDashboardScreen` (`lib/views/support/dashboard.dart`):
/// one screen with a 40pt segmented control (FAQ / Feedback / Delete Account)
/// above an animated page area. `AppRoute.faqs` / `.feedback` /
/// `.deleteAccount` open this same screen on the matching tab.
struct HelpView: View {
    @State private var selectedIndex: Int

    private static let titles: [LocalizedStringKey] = ["FAQ", "Feedback", "Delete Account"]

    init(initialIndex: Int = 0) {
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 10)
            segments
            Spacer().frame(height: 16)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedIndex)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: selectedIndex)
        .parityScaffold()
        .parityNavTitle("Help & Support")
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(Self.titles.indices, id: \.self) { index in
                let isSelected = selectedIndex == index
                Button {
                    selectedIndex = index
                } label: {
                    Text(Self.titles[index])
                        .font(AccountParity.font(12, .medium))
                        .tracking(0.1)
                        .foregroundStyle(isSelected ? AccountParity.black : AccountParity.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? AccountParity.white : Color.clear)
                        )
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 16)
        // Native-only tablet/Mac adaptation (no Flutter counterpart): the same
        // readable column as the tab pages below.
        .readableContentWidth()
    }

    @ViewBuilder
    private var page: some View {
        switch selectedIndex {
        case 0: FAQContentView()
        case 1: FeedbackContentView()
        default: DeleteAccountContentView()
        }
    }
}
