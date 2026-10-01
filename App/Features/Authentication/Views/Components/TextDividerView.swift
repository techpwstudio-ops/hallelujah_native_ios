import SwiftUI

/// Ported from `TextDivider` (`lib/widgets/text_divider.dart`): a centred
/// label between two hairlines. Padding values (12 horizontal on the label,
/// 4 all around the row) are Dart's own literals (`.px12()`/`.p4()`), not
/// this design system's `Spacing` scale — Dart doesn't route this widget
/// through `AppSpacing` either.
struct TextDividerView: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.gray)
                .frame(height: 0.25)
            Text(text)
                .typography(Typography.bodySmall)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color.gray)
                .frame(height: 0.25)
        }
        .padding(4)
    }
}
