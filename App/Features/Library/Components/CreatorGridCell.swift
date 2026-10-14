import SwiftUI

/// Ports `CreatorGridItem` (`lib/widgets/creator/creator_grid_item.dart`) as
/// laid out by `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:
/// 100, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.75)`:
/// an 80pt circular avatar (`sm`), 8pt gap and a centred `bodySmall` w500 name
/// (ellipsised), top-aligned in a `width / 0.75` tall cell.
struct CreatorGridCell: View {
    let creator: Creator
    var isSelected = false
    let onTap: () -> Void

    static let avatarSize: CGFloat = 80
    private static let nameStyle = TypographyToken(size: 12, weight: .medium, lineHeightMultiple: 1.5)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ArtworkView(
                    url: ArtworkURLResolver().resolve(path: creator.image, variant: .sm, allowedVariants: creator.imageVariants),
                    width: Self.avatarSize,
                    height: Self.avatarSize,
                    cornerRadius: 48
                )
                if isSelected {
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(4)
                        .background(Circle().fill(Color.white))
                }
            }
            Spacer().frame(height: 8)
            Text(creator.name ?? "")
                .typography(Self.nameStyle)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .aspectRatio(0.75, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// `SliverGridDelegateWithMaxCrossAxisExtent(100, spacing 12)`: the column
/// count is `ceil(width / (100 + 12))`, columns share the width equally.
struct CreatorMaxExtentGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder var cell: (Item) -> Cell

    @State private var width: CGFloat = 361

    private var columnCount: Int {
        max(1, Int((width / 112).rounded(.up)))
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount),
            spacing: 12
        ) {
            ForEach(items) { item in
                cell(item)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
            }
        )
    }
}
