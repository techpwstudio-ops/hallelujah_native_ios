import SwiftUI

/// Ported from `TextDivider` (`lib/widgets/text_divider.dart`): a centred
/// label between two hairlines. Padding values (12 horizontal on the label,
/// 4 all around the row) are Dart's own literals (`.px12()`/`.p4()`), not
/// this design system's `Spacing` scale — Dart doesn't route this widget
/// through `AppSpacing` either.
struct TextDividerView: View {
    let text: LocalizedStringKey

    @Environment(\.displayScale) private var displayScale

    /// Dart's 0.25 logical-pixel line still paints a full device pixel; a 0.25pt
    /// `Rectangle` here covers a quarter of one and all but vanishes.
    private var lineHeight: CGFloat { 1 / displayScale }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.gray)
                .frame(height: lineHeight)
            Text(text)
                .typography(Typography.bodySmall)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color.gray)
                .frame(height: lineHeight)
        }
        .padding(4)
    }
}
