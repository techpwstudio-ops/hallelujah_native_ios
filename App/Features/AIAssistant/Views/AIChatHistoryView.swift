import SwiftUI

/// Lists past AI conversations; tap opens one, swipe deletes. Ports
/// `AiHistoryPage` (`lib/views/ai/ai_history_page.dart`) and
/// `showDeleteConversationDialog` (`lib/dialogs/delete_conversation_dialog.dart`).
///
/// Tapping a row sets `AIChatNavigationStore.pendingConversationID` (observed
/// by the AI tab root) and pops back, mirroring Flutter's
/// `aiOpenConversationProvider` + `NavigationService.back()`.
struct AIChatHistoryView: View {
    @State private var viewModel = AIConversationsViewModel()
    @State private var navigationStore: AIChatNavigationStore = DependencyContainer.current.resolve()
    @State private var pendingDeleteID: String?

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AIColors.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AIColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Chat History")
                        .typography(Typography.titleMedium)
                        .foregroundStyle(Color.white)
                }
            }
            .task { await viewModel.load() }
            .overlay {
                if pendingDeleteID != nil {
                    deleteDialog
                }
            }
            .animation(.easeOut(duration: 0.15), value: pendingDeleteID)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            AISpinner(tint: AIColors.white38, size: 20)
        } else if let error = viewModel.error, viewModel.conversations.isEmpty {
            errorView(message: error)
        } else if viewModel.conversations.isEmpty {
            emptyView
        } else {
            list
        }
    }

    private var emptyView: some View {
        VStack(spacing: Dimens.spacing12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: Dimens.listItemThumbnailSizeMd))
                .foregroundStyle(AIColors.white24)
            Text("No conversations yet")
                .typography(Typography.bodyLarge)
                .foregroundStyle(AIColors.white38)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(AIColors.white38)
            Text(message)
                .typography(Typography.bodyMedium)
                .foregroundStyle(AIColors.white54)
                .multilineTextAlignment(.center)
                .padding(.top, Dimens.spacing12)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("Retry")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(AIColors.gold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.top, Dimens.spacing16)
        }
        .padding(Dimens.paddingExtraLarge)
    }

    private var list: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                row(for: conversation)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // `load()` swaps this list for the spinner, which would cancel a plain
        // `.refreshable` task mid-request; an unstructured task survives that.
        .refreshable { await Task { await viewModel.load() }.value }
    }

    // MARK: - Row

    private func row(for conversation: AIConversation) -> some View {
        Button {
            navigationStore.pendingConversationID = conversation.id
            coordinator.pop()
        } label: {
            HStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Dimens.userThumbnailSize, height: Dimens.userThumbnailSize)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text((conversation.title ?? "").isEmpty ? "Conversation" : (conversation.title ?? ""))
                        .font(AIColors.font(14, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let snippet = conversation.lastMessageSnippet {
                        Text(snippet)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(AIColors.hint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(Self.formattedDate(conversation.updatedAt ?? conversation.createdAt))
                    .typography(Typography.labelSmall)
                    .foregroundStyle(AIColors.white38)
            }
            .frame(minHeight: conversation.lastMessageSnippet == nil ? 56 : 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparatorTint(AIColors.white12)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                pendingDeleteID = conversation.id
            } label: {
                Image(systemName: "trash")
            }
            .tint(AIColors.errorBackground)
        }
        .onAppear { loadMoreIfNeeded(after: conversation) }
    }

    private func loadMoreIfNeeded(after conversation: AIConversation) {
        guard let index = viewModel.conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        guard index >= viewModel.conversations.count - 2 else { return }
        Task { await viewModel.loadMore() }
    }

    // MARK: - Date

    /// Ports `_formatDate`: Today / Yesterday / `Nd ago` / `d/m/yyyy`.
    private static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let diffDays = Int(Date().timeIntervalSince(date) / 86_400)
        if diffDays == 0 { return "Today" }
        if diffDays == 1 { return "Yesterday" }
        if diffDays < 7 { return "\(diffDays)d ago" }
        let parts = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return "\(parts.day ?? 0)/\(parts.month ?? 0)/\(parts.year ?? 0)"
    }

    // MARK: - Delete dialog

    /// Material `AlertDialog` on `fillColor`: white title, white60 body,
    /// white60 "Cancel" and red-400 "Delete" text buttons.
    private var deleteDialog: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()
                .onTapGesture { pendingDeleteID = nil }

            VStack(alignment: .leading, spacing: 0) {
                Text("Delete conversation?")
                    .font(AIColors.font(24))
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 16)
                Text("This cannot be undone.")
                    .font(AIColors.font(14))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 24)
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        pendingDeleteID = nil
                    } label: {
                        Text("Cancel")
                            .font(AIColors.font(14, .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Button {
                        guard let id = pendingDeleteID else { return }
                        pendingDeleteID = nil
                        Task { await viewModel.deleteConversation(id: id) }
                    } label: {
                        Text("Delete")
                            .font(AIColors.font(14, .medium))
                            .foregroundStyle(AIColors.red400)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 312)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(AIColors.fill)
            }
            .padding(.horizontal, 40)
        }
        .transition(.opacity)
    }
}
