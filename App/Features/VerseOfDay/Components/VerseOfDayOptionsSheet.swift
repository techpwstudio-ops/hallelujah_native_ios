import SwiftUI

/// `showVerseOfDayOptionsSheet` (`lib/sheets/book/verse_of_day_options_sheet.dart`):
/// drag handle, an "Ask Emet" tile (24pt app logo; hidden when the verse has
/// no text to explain) and a "Hide for today" tile (outlined eye-off), 8pt
/// below. Tiles are 56pt, title in the default list-tile style (16pt).
struct VerseOfDayOptionsSheet: View {
    let verse: VerseOfDay
    let onHide: () -> Void
    let onAskEmet: () -> Void
    /// Dismisses the sheet (the presenter owns the binding).
    let onClose: () -> Void

    private var target: VerseInsightTarget { .fromVerseOfDay(verse) }

    var body: some View {
        VStack(spacing: 0) {
            ReadDragHandle()

            if !target.isEmpty {
                tile(title: "Ask Emet", leading: {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Dimens.iconSize, height: Dimens.iconSize)
                }) {
                    onAskEmet()
                    onClose()
                }
            }

            tile(title: "Hide for today", leading: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(ReadPalette.white)
                    .frame(width: Dimens.iconSize, height: Dimens.iconSize)
            }) {
                onHide()
                onClose()
            }

            Spacer().frame(height: 8)
        }
    }

    private func tile<Leading: View>(
        title: String,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        let leadingView = leading()
        return Button(action: action) {
            HStack(spacing: 16) {
                leadingView
                Text(title)
                    .readText(Typography.bodyLarge, weight: .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
