import SwiftUI

/// T45's "add songs" sheet, per the cross-agent CONTRACT: presented as a
/// plain `.sheet` from `UserPlaylistDetailView`, not `.appSheet`
/// (`AppSheetContainer` has no toolbar slot) — so this view owns its own
/// `NavigationStack` for the title bar and Cancel action, the way any sheet
/// needing chrome beyond glass + drag handle has to. No completion callback
/// or binding: it dismisses itself via `\.dismiss`, and the parent reloads
/// on `.sheet`'s own `onDismiss` instead.
struct AddSongsToPlaylistView: View {
    @State private var viewModel: AddSongsToPlaylistViewModel

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(playlistID: String) {
        _viewModel = State(initialValue: AddSongsToPlaylistViewModel(playlistID: playlistID))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchTextField(
                    text: Binding(
                        get: { viewModel.searchFieldText },
                        set: { viewModel.queryChanged($0) }
                    ),
                    placeholder: "Search songs",
                    onClear: { viewModel.queryChanged("") }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                content

                AppButton(
                    label: "Add (\(viewModel.selectedSongIDs.count) selected)",
                    action: {
                        Task {
                            await viewModel.submit()
                            dismiss()
                        }
                    },
                    isLoading: viewModel.isSubmitting,
                    enabled: !viewModel.selectedSongIDs.isEmpty
                )
                .padding(Spacing.md)
            }
            .background(theme.color(.backgroundPrimary))
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = viewModel.searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            EmptyStateView(icon: .search, title: "Search for songs to add")
                .frame(maxHeight: .infinity)
        } else if viewModel.isSearching {
            LoadingStateView()
                .frame(maxHeight: .infinity)
        } else if viewModel.songs.isEmpty {
            EmptyStateView(title: "No songs found")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.songs) { song in
                        AddSongsToPlaylistRow(
                            song: song,
                            isSelected: viewModel.selectedSongIDs.contains(song.id),
                            onToggle: { viewModel.toggleSelection(songID: song.id) }
                        )
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}
