import SwiftUI

/// T56 — ports `VerseOfDayCommentsPage` (`verse_of_day_comments_sheet.dart`):
/// a "Comments" header, a paginated newest-first list (empty state "You are
/// first to comment" when nobody has yet), and a bottom composer. Bare sheet
/// content per `LanguagePickerSheet.swift`'s doc comment — `.appSheet`
/// supplies the drag handle and glass chrome.
///
/// Scope cut from Dart's own sheet: no `showVerseOfDayUi` param — that flag
/// only fires from `book_page_menu_sheet.dart`'s reader-menu entry point
/// (out of T56's scope), never from `VerseOfDayUi`'s own comment tap, which
/// is this file's only call site (`VerseOfDayCardView.swift`).
struct VerseOfDayCommentsSheet: View {
    let verseOfDayId: String

    @State private var viewModel: VerseOfDayCommentsViewModel

    init(verseOfDayId: String) {
        self.verseOfDayId = verseOfDayId
        _viewModel = State(initialValue: VerseOfDayCommentsViewModel(verseOfDayId: verseOfDayId))
    }

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Comments")
                        .typography(Typography.bodyLarge)
                        .foregroundStyle(theme.color(.textSecondary))
                        .padding(.top, Spacing.md)

                    if viewModel.isLoadingComments, !viewModel.hasLoadedOnce {
                        LoadingStateView()
                    } else if viewModel.hasLoadedOnce, viewModel.comments.isEmpty {
                        EmptyStateView(title: "You are first to comment")
                    } else {
                        ForEach(viewModel.comments) { comment in
                            VerseOfDayCommentRow(
                                comment: comment,
                                onToggleLike: { Task { await viewModel.toggleCommentLike(comment) } }
                            )
                            .onAppear {
                                Task { await viewModel.loadMoreCommentsIfNeeded(currentItem: comment) }
                            }
                        }
                        if viewModel.isLoadingComments {
                            LoadingStateView()
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()
                .overlay(theme.color(.border))

            VerseOfDayCommentInputBar(
                isAddingComment: viewModel.isAddingComment,
                onSend: { content in Task { await viewModel.postComment(content: content) } }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .task {
            await viewModel.onAppear()
        }
    }
}

/// One comment row. Ports `VerseOfDayCommentItem`/`_LikeRow`
/// (`verse_comment_item.dart`): username + relative time-ago on top,
/// content below, a heart-and-count like row beneath. `RelativeDateTimeFormatter`
/// stands in for Dart's own `Formater.timeAgo` — same native-API-over-1:1-port
/// precedent `VerseOfDayCardViewModel`'s own doc comment already established.
private struct VerseOfDayCommentRow: View {
    let comment: VerseOfDayComment
    let onToggleLike: () -> Void

    @Environment(\.appTheme) private var theme

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var timeAgo: String? {
        guard let createdAt = comment.createdAt else { return nil }
        return Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(comment.userName ?? "Anonymous")
                    .typography(Typography.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer(minLength: Spacing.sm)
                if let timeAgo {
                    Text(timeAgo)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                }
            }
            Text(comment.content)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))

            Button(action: onToggleLike) {
                HStack(spacing: Spacing.xs) {
                    theme.icon(comment.isLiked ? .favoriteFilled : .favorite)
                        .font(.system(size: 16))
                    if comment.likes > 0 {
                        Text("\(comment.likes)")
                            .typography(Typography.bodySmall)
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(comment.isLiked ? theme.color(.statusError) : theme.color(.textSecondary))
            }
            .buttonStyle(.plain)
            .animation(MotionCurve.fast, value: comment.likes)
        }
    }
}

/// The composer at the sheet's bottom. Ports `VerseOfDayCommentInput`
/// (`verse_comment_input.dart`): a 2-5 line growing text field capped at 200
/// characters, an emoji row that appends to it, and a trailing send action —
/// reusing `AppButton` for that last part rather than hand-building Dart's
/// own bespoke 64x32 pill, since `AppButton` already covers every state
/// (disabled while empty, spinner while `isAddingComment`) this needs.
private struct VerseOfDayCommentInputBar: View {
    let isAddingComment: Bool
    let onSend: (String) -> Void

    @State private var text = ""
    @Environment(\.appTheme) private var theme

    private static let maxLength = 200

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField("Type your comment here", text: $text, axis: .vertical)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(2...5)
                .onChange(of: text) { _, newValue in
                    if newValue.count > Self.maxLength {
                        text = String(newValue.prefix(Self.maxLength))
                    }
                }

            HStack(spacing: Spacing.md) {
                VerseOfDayEmojiReactionBar { emoji in
                    text += emoji
                }
                Spacer(minLength: 0)
                AppButton(
                    label: "Send",
                    action: handleSend,
                    isLoading: isAddingComment,
                    enabled: !trimmedText.isEmpty && !isAddingComment,
                    width: 88
                )
            }
        }
    }

    private func handleSend() {
        guard !trimmedText.isEmpty, !isAddingComment else { return }
        let content = trimmedText
        text = ""
        onSend(content)
    }
}

/// A fixed row of tappable emoji that append themselves to the comment
/// field. Ports `VerseReactionBar` (`verse_reaction_bar.dart`) at this
/// file's only call site's actual usage: `reactions` is always passed empty
/// there, so the per-emoji count Dart's own widget supports never renders in
/// practice — omitted here rather than porting dead functionality.
private struct VerseOfDayEmojiReactionBar: View {
    let onReact: (String) -> Void

    private static let emojis = ["🙏", "❤️", "🔥", "🙌", "✨", "📖"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
