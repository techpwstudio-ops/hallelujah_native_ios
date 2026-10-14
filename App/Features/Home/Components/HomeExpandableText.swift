import SwiftUI

private struct HomeTextHeightsKey: PreferenceKey {
    struct Heights: Equatable {
        var clamped: CGFloat = 0
        var full: CGFloat = 0
    }

    static let defaultValue = Heights()
    static func reduce(value: inout Heights, nextValue: () -> Heights) {
        let next = nextValue()
        if next.clamped > 0 { value.clamped = next.clamped }
        if next.full > 0 { value.full = next.full }
    }
}

/// `ExpandableText` — `maxLines` (3) of text with an ellipsis and, only when
/// the text really overflows, a bold "Read more" / "Read less" toggle (4pt
/// below) in the same style.
struct HomeExpandableText: View {
    let text: String
    let token: TypographyToken
    let color: Color
    var maxLines = 3

    @State private var isExpanded = false
    @State private var heights = HomeTextHeightsKey.Heights()

    private var overflows: Bool { heights.full > heights.clamped + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .typography(token)
                .foregroundStyle(color)
                .lineLimit(isExpanded ? nil : maxLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    // Measures the same text unclamped, to know whether the
                    // clamp is hiding anything.
                    Text(text)
                        .typography(token)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: HomeTextHeightsKey.self,
                                    value: HomeTextHeightsKey.Heights(clamped: 0, full: proxy.size.height)
                                )
                            }
                        )
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeTextHeightsKey.self,
                            value: HomeTextHeightsKey.Heights(clamped: isExpanded ? 0 : proxy.size.height, full: 0)
                        )
                    }
                )
            if overflows || isExpanded {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Read less" : "Read more")
                        .typography(token)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
        }
        .onPreferenceChange(HomeTextHeightsKey.self) { heights = $0 }
    }
}
