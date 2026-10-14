import SwiftUI

/// Ports `QueuePage` (`lib/views/player/queue_page.dart`), which Flutter
/// presents through `showQueueSheet` -> `showAppSheet` as a
/// `DraggableScrollableSheet` (initial 0.8, min 0.5, max 0.95). The player
/// presents this as a sheet (`isSheet: true`) with those detents; the legacy
/// `PlayerRoute.queue` push (the song menu's "Queue" row) still constructs it
/// with the default and gets a navigation bar instead of the sheet header.
///
/// Header: 8pt padding (12 below), "Queue" in `titleMedium` w600 white. Rows
/// show the whole queue; the current row has a white @ 8% 8pt-radius
/// background, the rest are 70% opaque; tapping jumps to it; each row carries
/// a trailing drag handle (`MenuIcon`, always visible) that reorders. Empty:
/// centred "Queue is empty" in `bodyMedium` w300 white @ 70%. Flutter has no
/// remove affordance, so none is offered.
struct QueueView: View {
    var isSheet: Bool = false

    @State private var queueController: QueueController = DependencyContainer.current.resolve()

    static let sheetDetents: Set<PresentationDetent> = [.fraction(0.8), .fraction(0.95)]

    private var songs: [Song] { queueController.queue?.songs ?? [] }
    private var currentIndex: Int? { queueController.queue?.currentIndex }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSheet {
                Text("Queue")
                    .typography(PlayerStyle.titleMediumSemibold)
                    .foregroundStyle(PlayerStyle.white)
                    .padding(.top, 16)
                    .padding(.horizontal, Dimens.screenPaddingAll)
                    .padding(.bottom, 12)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isSheet ? Color.clear : PlayerStyle.black)
        .modifier(QueueNavigationChrome(isSheet: isSheet))
    }

    @ViewBuilder
    private var content: some View {
        if songs.isEmpty {
            Text("Queue is empty")
                .typography(TypographyToken(size: 14, weight: .light, lineHeightMultiple: 1.5))
                .foregroundStyle(PlayerStyle.whiteAlpha(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    QueueSongRow(song: song, isCurrent: index == currentIndex)
                        .opacity(index == currentIndex ? 1 : 0.7)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                                .fill(index == currentIndex ? PlayerStyle.whiteAlpha(0.08) : Color.clear)
                        )
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await queueController.jump(to: index) }
                        }
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 24, for: .scrollContent)
            // Always-visible trailing drag handles, like Flutter's per-row
            // `ReorderableDragStartListener`.
            .environment(\.editMode, .constant(.active))
        }
    }

    /// `ReorderQueueItemPlayerEvent(oldIndex, newIndex)` takes the
    /// post-removal target index; `.onMove` hands an insertion point in the
    /// pre-removal array.
    private func move(from source: IndexSet, to destination: Int) {
        guard source.count == 1, let oldIndex = source.first else { return }
        let newIndex = oldIndex < destination ? destination - 1 : destination
        guard newIndex != oldIndex else { return }
        Task { await queueController.reorder(from: oldIndex, to: newIndex) }
    }
}

/// Navigation-bar title for the pushed (non-sheet) presentation only.
private struct QueueNavigationChrome: ViewModifier {
    let isSheet: Bool

    func body(content: Content) -> some View {
        if isSheet {
            content
        } else {
            content
                .navigationTitle("Queue")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
