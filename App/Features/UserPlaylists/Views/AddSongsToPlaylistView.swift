import SwiftUI

/// The native answer to `ContentSearchPage`'s `isSelect` mode for songs
/// (`content_search_page.dart` + `AddToPlaylistCheckBox` +
/// `ContinueToAddPlaylist`). Pushed like Flutter's route
/// (`.contentSearch(isSelect: true)`), not a sheet: it's the Search page —
/// same glass search bar with voice search, same rows — with checkboxes.
///
/// Looks like that page: a 200pt `#282828 -> #1C1C1C -> black` gradient behind
/// the 52pt `#333333` search bar (back arrow, "What do you want to listen
/// to?"), result rows with a trailing checkbox, shimmer while searching, the
/// "No results found / Try searching with a different keyword" empty state
/// (also shown for an empty field in select mode) and a bottom-right
/// "Continue" pill once something is selected. A row tap toggles its
/// checkbox (Dart's row tap plays the song instead — there is no player to
/// open from inside a sheet).
struct AddSongsToPlaylistView: View {
    @State private var viewModel: AddSongsToPlaylistViewModel
    @FocusState private var isFieldFocused: Bool
    @State private var isListening = false

    @Environment(AppNavigationCoordinator.self) private var coordinator

    init(playlistID: String) {
        _viewModel = State(initialValue: AddSongsToPlaylistViewModel(playlistID: playlistID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [ParityColor.darkFill, ParityColor.darkSurface, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                searchBar
                content
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.selectedSongIDs.isEmpty {
                ParityContinueButton(isDisabled: viewModel.isSubmitting) {
                    Task {
                        await viewModel.submit()
                        coordinator.pop()
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isFieldFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Dimens.paddingMedium)
            Button { coordinator.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer().frame(width: Dimens.paddingMedium)

            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchFieldText },
                    set: { viewModel.queryChanged($0) }
                ),
                prompt: Text(isListening ? "Listening\u{2026}" : "What do you want to listen to?").foregroundColor(ParityColor.grey)
            )
            .typography(Typography.bodyMedium)
            .foregroundStyle(Color.white)
            .tint(ParityColor.white70)
            .focused($isFieldFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()

            if !viewModel.searchFieldText.isEmpty {
                Button { viewModel.queryChanged("") } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundStyle(ParityColor.white60)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            VoiceSearchButton(
                onResult: { text, _ in viewModel.queryChanged(text) },
                onListeningChanged: { listening in
                    isListening = listening
                    if listening { isFieldFocused = false }
                }
            )
            Spacer().frame(width: Dimens.spacing4)
        }
        .frame(height: Dimens.buttonHeight)
        .glassRounded(Dimens.cornerRadiusSmall + 2)
        .padding(.leading, Dimens.screenPadding)
        .padding(.trailing, Dimens.screenPadding)
        .padding(.top, Dimens.spacing8)
        .padding(.bottom, Dimens.paddingMedium)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.searchFieldText.isEmpty {
            ParityEmptyState(
                systemImage: "magnifyingglass",
                title: "No results found",
                message: "Try searching with a different keyword"
            )
        } else if viewModel.isSearching {
            ScrollView { ParityShimmerList() }
                .scrollDisabled(true)
        } else if viewModel.songs.isEmpty {
            ParityEmptyState(
                systemImage: "magnifyingglass",
                title: "No results found",
                message: "Try searching with a different keyword"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: Dimens.spacing8)
                    ForEach(viewModel.songs) { song in
                        SearchSongRow(
                            song: song,
                            isChecked: viewModel.selectedSongIDs.contains(song.id),
                            onTap: { viewModel.toggleSelection(songID: song.id) }
                        )
                        .padding(.horizontal, Dimens.screenPadding)
                        .padding(.vertical, Dimens.spacing4)
                    }
                    Color.clear.frame(height: 16)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}
