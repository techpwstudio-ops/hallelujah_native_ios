import SwiftUI

/// Ports `CreatorGridPage` (`lib/views/library/grid_artists.dart`): app bar
/// "Choose artists you like.", the tap-through search bar, a max-100pt
/// `CreatorGridCell` grid (16pt side padding) with check marks, pull-to-
/// refresh, and a floating white "Done" button that appears once the
/// selection differs from the followed set.
struct CreatorGridView: View {
    let title: String
    let songType: String

    @State private var viewModel: CreatorGridViewModel
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    init(title: String, songType: String) {
        self.title = title
        self.songType = songType
        _viewModel = State(initialValue: CreatorGridViewModel(songType: songType))
    }

    var body: some View {
        ScrollView {
            ParityFakeSearchBar {
                coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
            .padding(.vertical, Dimens.screenPaddingAll)

            if viewModel.creators.isEmpty && !viewModel.hasLoadedOnce {
                ParitySpinner(fills: true)
            } else {
                CreatorMaxExtentGrid(items: viewModel.creators) { creator in
                    CreatorGridCell(creator: creator, isSelected: viewModel.isSelected(creator)) {
                        viewModel.toggle(creator)
                    }
                    .task { await viewModel.loadMoreIfNeeded(currentItem: creator) }
                }
                .padding(.horizontal, Dimens.screenPaddingAll * 2)
                .padding(.vertical, Dimens.screenPaddingAll)
                if viewModel.isLoading { ParitySpinner() }
            }
            Color.clear.frame(height: 16)
        }
        .refreshable { await viewModel.refresh() }
        .background(Color.black)
        .parityNavTitle {
            Text("Choose artists you like.")
                .font(.custom(Typography.fontFamily, size: 20).weight(.black))
                .foregroundStyle(Color.white)
        }
        .overlay(alignment: .bottom) { doneButton }
        .task { await viewModel.onAppear() }
        .toastOverlay()
    }

    @ViewBuilder
    private var doneButton: some View {
        if viewModel.hasChanges {
            Button {
                Task {
                    if await viewModel.done() {
                        coordinator.pop()
                    } else {
                        toastCenter.show("Something went wrong. Please try again.")
                    }
                }
            } label: {
                Text("Done")
                    .typography(Typography.labelLarge)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .glassCapsule(.tinted(.brandPrimary), interactive: true)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
            .padding(.bottom, 96)
        }
    }
}
