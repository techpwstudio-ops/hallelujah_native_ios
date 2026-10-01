import SwiftUI

/// T58 — the destination for the app's existing `AppRoute.aiHistory` route:
/// a conversation list backed by `AIConversationsViewModel`
/// (`GET /ai/conversations`, create, delete).
///
/// This screen owns no navigation of its own beyond popping itself: tapping
/// a row sets `AIChatNavigationStore.pendingConversationID` (the shared,
/// container-resolved instance also read by the AI tab's home screen — see
/// that store's own doc comment for why a shared signal, not a direct
/// closure, is the bridge between these two independently-pushed screens)
/// and pops back to the tab root, which is expected to notice the pending id
/// and switch to that conversation.
///
/// List style follows this codebase's `List` + `.listStyle(.plain)` +
/// `.scrollContentBackground(.hidden)` convention (`MyNotesView.swift`,
/// `HelpView.swift`) rather than the `ScrollView`/`LazyVStack` convention
/// `UserPlaylistDetailView.swift`/`DownloadsView.swift` use elsewhere:
/// `UserPlaylistDetailView.swift`'s own row comment documents that
/// `.swipeActions` silently no-ops outside a real `List`, and swipe-to-delete
/// is a hard requirement here, so `List` is the only one of this codebase's
/// two existing list conventions that can actually satisfy it.
struct AIChatHistoryView: View {
    @State private var viewModel = AIConversationsViewModel()
    @State private var navigationStore: AIChatNavigationStore = DependencyContainer.current.resolve()
    @State private var pendingDeleteID: String?

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        content
            .background(theme.color(.backgroundPrimary))
            .task { await viewModel.load() }
            .confirmationDialog(
                "Delete this conversation?",
                isPresented: isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = pendingDeleteID else { return }
                    pendingDeleteID = nil
                    Task { await viewModel.deleteConversation(id: id) }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteID = nil
                }
            }
    }

    // MARK: - Content

    /// Loading takes priority over a stale `error` from a previous attempt;
    /// `error` (only ever set once a fetch has actually finished) then
    /// chooses between `ErrorStateView`'s retry affordance and
    /// `EmptyStateView`'s plain "nothing here yet" — the same
    /// loading/failed/empty split `UserPlaylistDetailView.swift` draws across
    /// its own `LoadState`, reusing the identical pair of state-view
    /// components it uses for its `.failed`/`.empty` cases.
    @ViewBuilder
    private var content: some View {
        if viewModel.conversations.isEmpty {
            if viewModel.isLoading {
                LoadingStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.error != nil {
                ErrorStateView(
                    title: "Couldn't load conversations",
                    message: viewModel.error,
                    onRetry: { Task { await viewModel.load() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: .tabAI,
                    title: "No conversations yet",
                    message: "Start a new chat to see it here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                row(for: conversation)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Row

    private func row(for conversation: AIConversation) -> some View {
        Button {
            navigationStore.pendingConversationID = conversation.id
            coordinator.pop()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(conversation.title ?? "New conversation")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                if let snippet = conversation.lastMessageSnippet, !snippet.isEmpty {
                    Text(snippet)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .lineLimit(2)
                }
                if let dateText = Self.formattedDate(conversation.updatedAt ?? conversation.createdAt) {
                    Text(dateText)
                        .typography(Typography.labelSmall)
                        .foregroundStyle(theme.color(.textTertiary))
                }
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDeleteID = conversation.id
            } label: {
                theme.icon(.trash)
            }
        }
        .onAppear { loadMoreIfNeeded(after: conversation) }
    }

    // MARK: - Pagination

    /// Same "within 2 of the end" threshold `UserPlaylistDetailView.swift`'s
    /// `songList` uses for its own infinite scroll.
    private func loadMoreIfNeeded(after conversation: AIConversation) {
        guard let index = viewModel.conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        guard index >= viewModel.conversations.count - 2 else { return }
        Task { await viewModel.loadMore() }
    }

    // MARK: - Formatting

    private static func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    private var isDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteID = nil }
            }
        )
    }
}
