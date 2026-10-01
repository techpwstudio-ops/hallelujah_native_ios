import SwiftUI

/// Ports `DownloadsPage` (`lib/views/library/downloads.dart`) — Dart shows
/// only the already-completed song list (no in-progress states at all, since
/// `flutter_downloader`'s own bloc never surfaces one); this screen is wider
/// by contract (T46's locked contract), since `DownloadEngine` actually
/// models `.queued`/`.downloading`/`.paused`/`.failed` states Dart's bare
/// `DownloadBloc.songs`/`episodes` id lists have no equivalent for.
///
/// No music/podcast filter row either — Dart's `songType` toggle has exactly
/// one real call site pushing this route today (`LibraryHomeView`'s
/// Downloads quick link, always `type: "all"`), so `type` is accepted
/// (matching `AppRoute.downloads`'s payload shape) but unused: a filter UI
/// with no live caller would be speculative scope, not a gap. Add real
/// filtering here if and when a second call site needs it.
///
/// No view model — `DownloadEngine` (T46) is itself `@Observable` and this
/// screen does nothing but read its `tasks` dictionary and forward taps to
/// its mutating methods, with no network fetch/pagination of its own to
/// manage (unlike `UserPlaylistDetailViewModel`'s heavier resolve-and-load
/// shape). Resolved the same direct way `UserPlaylistDetailView` already
/// resolves `QueueController`/`AudioEngine`.
///
/// Tap-to-play on a `.completed` row is deliberately left out — wiring a
/// downloaded file into playback is T47 (Offline playback)'s job, not this
/// one's (see T46's own scope boundary); rows here are plain, non-tappable
/// display-plus-control surfaces only.
struct DownloadsView: View {
    let type: String

    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()
    @State private var isDeleteAllConfirmationPresented = false

    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let thumbnailSize: CGFloat = 56

    var body: some View {
        ScrollView {
            if downloadEngine.tasks.isEmpty {
                EmptyStateView(title: "No downloads yet")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sortedTasks) { task in
                        row(for: task)
                            .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Storage") { coordinator.push(.storageSettings) }
            }
            if !downloadEngine.tasks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete All", role: .destructive) {
                        isDeleteAllConfirmationPresented = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete all downloads?",
            isPresented: $isDeleteAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                downloadEngine.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sorting

    /// In-progress first (`.downloading`/`.queued`/`.paused`), then
    /// `.completed`, then `.failed` — T46's locked contract's own row
    /// ordering. Most-recently-enqueued first within each group.
    private var sortedTasks: [DownloadTask] {
        downloadEngine.tasks.values.sorted { lhs, rhs in
            let lhsRank = sortRank(for: lhs.state)
            let rhsRank = sortRank(for: rhs.state)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func sortRank(for state: DownloadState) -> Int {
        switch state {
        case .downloading, .queued, .paused: 0
        case .completed: 1
        case .failed: 2
        }
    }

    // MARK: - Row

    private func row(for task: DownloadTask) -> some View {
        HStack(spacing: Spacing.md) {
            ArtworkView(
                url: ArtworkURLResolver().resolve(
                    path: task.songArtworkPath,
                    variant: .sm,
                    allowedVariants: task.songArtworkVariants
                ),
                width: Self.thumbnailSize,
                height: Self.thumbnailSize
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(task.songTitle)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                if let genre = task.songGenreName {
                    Text(genre)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            trailingControl(for: task)
        }
        .padding(.vertical, Spacing.xs)
    }

    /// One state-appropriate trailing affordance per `DownloadState` — the
    /// exact set T46's locked contract specifies.
    @ViewBuilder
    private func trailingControl(for task: DownloadTask) -> some View {
        switch task.state {
        case .queued:
            Text("Waiting…")
                .typography(Typography.labelMedium)
                .foregroundStyle(theme.color(.textTertiary))

        case .downloading:
            HStack(spacing: Spacing.sm) {
                if let totalBytes = task.totalBytes, totalBytes > 0 {
                    ProgressView(value: Double(task.bytesWritten), total: Double(totalBytes))
                        .frame(width: 60)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Button {
                    downloadEngine.pause(songID: task.songID)
                } label: {
                    theme.icon(.pause)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
            }

        case .paused:
            HStack(spacing: Spacing.sm) {
                Button {
                    downloadEngine.resume(songID: task.songID)
                } label: {
                    theme.icon(.play)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                Button {
                    downloadEngine.cancel(songID: task.songID)
                } label: {
                    theme.icon(.trash)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
            }

        case .completed:
            Button {
                downloadEngine.deleteDownload(songID: task.songID)
            } label: {
                theme.icon(.trash)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)

        case .failed:
            HStack(spacing: Spacing.sm) {
                Text("Failed")
                    .typography(Typography.labelMedium)
                    .foregroundStyle(theme.color(.statusError))
                Button {
                    Task { await downloadEngine.retry(songID: task.songID) }
                } label: {
                    theme.icon(.retry)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                Button {
                    downloadEngine.cancel(songID: task.songID)
                } label: {
                    theme.icon(.trash)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
