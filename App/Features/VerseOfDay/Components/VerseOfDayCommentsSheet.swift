import SwiftUI

/// `showVerseOfDayComments` / `VerseOfDayCommentsPage`
/// (`lib/sheets/book/verse_of_day_comments_sheet.dart`): drag handle, a list
/// (24pt side padding, 32pt between rows) whose first row is — optionally the
/// verse card (`showsVerseOfDay`, 16pt above/below), the "Comments" caption
/// (bodyLarge, white 70%), a 12pt gap and "You are first to comment" when
/// empty — followed by the comments; a divider; and the composer.
struct VerseOfDayCommentsSheet: View {
    let verseOfDayId: String
    var showsVerseOfDay = false

    @State private var viewModel: VerseOfDayCommentsViewModel

    init(verseOfDayId: String, showsVerseOfDay: Bool = false) {
        self.verseOfDayId = verseOfDayId
        self.showsVerseOfDay = showsVerseOfDay
        _viewModel = State(initialValue: VerseOfDayCommentsViewModel(verseOfDayId: verseOfDayId))
    }

    var body: some View {
        VStack(spacing: 0) {
            ReadDragHandle()

            if viewModel.isLoadingComments, !viewModel.hasLoadedOnce {
                ReadSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 0) {
                            if showsVerseOfDay {
                                VerseOfDayCardView()
                                    .padding(.vertical, 16)
                            }
                            Text("Comments")
                                .readText(Typography.bodyLarge, weight: .regular, color: ReadPalette.secondaryText)
                            Spacer().frame(height: 12)
                            if viewModel.hasLoadedOnce, viewModel.comments.isEmpty {
                                ReadEmptyText(text: "You are first to comment")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

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
                            ReadSpinner()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            Rectangle()
                .fill(ReadPalette.divider)
                .frame(height: 1)
                .padding(.vertical, 8)

            VerseOfDayCommentInputBar(
                isAddingComment: viewModel.isAddingComment,
                onSend: { content in Task { await viewModel.postComment(content: content) } }
            )
            .padding(.top, Dimens.screenPaddingAll)
        }
        .task {
            await viewModel.onAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .verseOfDayCommentAdded)) { note in
            guard let comment = note.userInfo?["comment"] as? VerseOfDayComment else { return }
            Task { @MainActor in viewModel.applyLiveComment(comment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .verseOfDayCommentLikesChanged)) { note in
            guard let info = note.userInfo,
                  let commentId = info["commentId"] as? String,
                  let likes = info["likes"] as? Int,
                  let verseOfDayId = info["verseOfDayId"] as? String else { return }
            Task { @MainActor in
                viewModel.applyLiveLikes(commentId: commentId, likes: likes, verseOfDayId: verseOfDayId)
            }
        }
    }
}

/// `Formater.timeAgo`: "just now", "N min", "N hour(s)", "N day(s)",
/// "N month(s)", "N year(s)".
private func verseOfDayTimeAgo(_ date: Date?) -> String {
    guard let date else { return "" }
    let seconds = Int(Date().timeIntervalSince(date))
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24
    if seconds < 60 { return "just now" }
    if minutes < 60 { return "\(minutes) min" }
    if hours < 24 { return "\(hours) hour\(hours > 1 ? "s" : "")" }
    if days < 30 { return "\(days) day\(days > 1 ? "s" : "")" }
    if days < 365 {
        let months = days / 30
        return "\(months) month\(months > 1 ? "s" : "")"
    }
    let years = days / 365
    return "\(years) year\(years > 1 ? "s" : "")"
}

/// `VerseOfDayCommentItem`: name (bodyLarge w600, "Anonymous" fallback) and
/// time-ago (bodySmall, 60%) on one row, 6pt, the comment (bodyMedium,
/// height 1.4), 10pt, then the like row (20pt heart in white 60% + count).
private struct VerseOfDayCommentRow: View {
    let comment: VerseOfDayComment
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(comment.userName ?? "Anonymous")
                    .readText(Typography.bodyLarge, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verseOfDayTimeAgo(comment.createdAt))
                    .readText(Typography.bodySmall, color: ReadPalette.white60)
            }
            Spacer().frame(height: 6)
            Text(comment.content)
                .readText(Typography.bodyMedium)
                .lineSpacing(14 * 0.2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 10)
            Button(action: onToggleLike) {
                HStack(spacing: 0) {
                    VerseOfDayHeartIcon(isLiked: comment.isLiked, size: 20, color: ReadPalette.white60)
                        .scaleEffect(comment.isLiked ? 1.2 : 1.0)
                        .animation(.easeOut(duration: 0.18), value: comment.isLiked)
                    VerseOfDayAnimatedCount(count: comment.likes, color: ReadPalette.white60)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// `VerseOfDayCommentInput`: borderless 2–5 line field (200 chars, hint "Type
/// your comment here"), then the emoji strip and a 64x32 "Send" button.
private struct VerseOfDayCommentInputBar: View {
    let isAddingComment: Bool
    let onSend: (String) -> Void

    @State private var text = ""

    private static let maxLength = 200

    private var canSend: Bool { !text.isEmpty && !isAddingComment }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "",
                text: $text,
                prompt: Text("Type your comment here")
                    .font(.custom(Typography.fontFamily, size: 12, relativeTo: .body).weight(.medium))
                    .foregroundColor(ReadPalette.hint),
                axis: .vertical
            )
            .typography(Typography.bodyLarge)
            .foregroundStyle(ReadPalette.white)
            .lineLimit(2...5)
            .frame(minHeight: 48, alignment: .topLeading)
            .onChange(of: text) { _, newValue in
                if newValue.count > Self.maxLength {
                    text = String(newValue.prefix(Self.maxLength))
                }
            }

            HStack(spacing: 0) {
                VerseOfDayEmojiReactionBar { emoji in
                    text += emoji
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: Dimens.horizontalSpacing)
                sendButton
            }
        }
        .padding(.horizontal, 24)
    }

    private var sendButton: some View {
        Button(action: handleSend) {
            Group {
                if isAddingComment {
                    ReadSpinner(size: 24)
                        .padding(8)
                } else {
                    Text("Send")
                        .readText(Typography.labelMedium, weight: .semibold)
                }
            }
            .frame(width: 64, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ReadPalette.commentInputBorder)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.7)
    }

    private func handleSend() {
        guard canSend else { return }
        let content = text
        text = ""
        onSend(content)
    }
}

/// `VerseReactionBar`: six emoji (titleMedium, 12/6 padding, 8pt apart) in a
/// 42pt-high strip.
private struct VerseOfDayEmojiReactionBar: View {
    let onReact: (String) -> Void

    private static let emojis = ["\u{1F64F}", "\u{2764}\u{FE0F}", "\u{1F525}", "\u{1F64C}", "\u{2728}", "\u{1F4D6}"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                            .typography(Typography.titleMedium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 42)
    }
}
