import SwiftUI

/// Ports `RecentSongsPage` (`lib/views/home/recent_songs_page.dart`): a pinned
/// "Recent" bar (bold), a Music / Podcast switcher (36pt buttons, 16 apart,
/// 8 inset, defaulting to Music) and the user's recent songs for that type,
/// paginated — `recent-music` / `recent-episode` on the wire.
struct RecentSongsView: View {
    @State private var selected: HomeContentType = .music

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                tabs
                RecentSongsList(type: selected)
                    .id(selected)
                Color.clear.frame(height: HomeMetrics.pageBottomSpacing)
            }
        }
        .background(HomeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // `centerTitle: false` — left-aligned beside the back button.
            ToolbarItem(placement: .topBarLeading) {
                Text("Recent")
                    .typography(Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
            }
        }
    }

    private struct SwitcherTab: Identifiable {
        let type: HomeContentType
        let name: String
        var id: String { type.rawValue }
    }

    private var tabs: some View {
        HStack(spacing: Dimens.horizontalSpacing) {
            ForEach([SwitcherTab(type: .music, name: "Music"), SwitcherTab(type: .episode, name: "Podcast")]) { tab in
                let isSelected = selected == tab.type
                Button {
                    selected = tab.type
                } label: {
                    Text(tab.name)
                        .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.medium))
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .padding(.horizontal, Dimens.spacing8)
                        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                        .frame(minWidth: 90)
                        .background(
                            isSelected ? Color.white : HomeColors.fill,
                            in: RoundedRectangle(cornerRadius: 8, style: .circular)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Dimens.spacing8)
        .padding(.vertical, Dimens.screenPaddingAll)
    }
}

/// The recent list for one content type; recreated (via `.id`) when the
/// switcher flips, like `HomeViewMoreLoadEvent` resetting on a new uiId.
private struct RecentSongsList: View {
    @State private var viewModel: SectionDetailViewModel
    let uiId: String

    private static let paginationRunway = 4

    init(type: HomeContentType) {
        uiId = "recent-\(type.rawValue)"
        _viewModel = State(initialValue: SectionDetailViewModel(uiId: "recent-\(type.rawValue)", title: "Recent", contentType: type))
    }

    private var songs: [Song] {
        if case .loaded(let content) = viewModel.state, case .songs(let page) = content {
            return page.items
        }
        return []
    }

    var body: some View {
        content
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HomeSpinner()
                .frame(maxWidth: .infinity, minHeight: 300)
        case .empty, .failed:
            HomeEmptyText(text: String(localized: "No Recent Music/Episodes"))
                .frame(minHeight: 300)
        case .loaded:
            if songs.isEmpty {
                HomeEmptyText(text: String(localized: "No Recent Music/Episodes"))
                    .frame(minHeight: 300)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        HomeSongListRow(
                            song: song,
                            songs: songs,
                            source: HomePlayback.homeAttribution(uiId: uiId)
                        )
                        .onAppear {
                            if index >= songs.count - Self.paginationRunway { viewModel.loadMore() }
                        }
                    }
                    if viewModel.isLoadingMore {
                        HomePageLoadingRow()
                    }
                }
                .padding(.horizontal, Dimens.screenPaddingAll)
            }
        }
    }
}
