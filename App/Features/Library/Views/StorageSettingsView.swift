import SwiftUI

/// T47 (Offline playback) — a storage-management screen for downloaded
/// songs: total on-disk space, how many are fully downloaded, and a way to
/// wipe them all. No Dart precedent to port — grepping `lib/` for
/// `storage_settings`/`StoragePage` turns up nothing beyond an unrelated
/// generic key-value `StorageService` — so this is a native-only addition.
/// T70 (Profile and settings), which would normally host a general
/// settings list this could live inside, hasn't shipped yet either (still
/// unchecked in `progress.md`), so this is a standalone screen for now.
///
/// No view model, same reasoning `DownloadsView` (T46) already documents:
/// `DownloadEngine` is itself `@Observable`, and this screen does nothing
/// but read it, so a view model would only add indirection. Resolved the
/// same direct way `DownloadsView` resolves it.
///
/// No route exists to reach this screen yet and none is added here — it
/// takes no arguments and compiles standalone, with no navigation wiring
/// needed to construct it. No `#Preview` either, same gap every other
/// `DependencyContainer`-resolving view in `Library/Views` already has
/// (`FavouriteSongsView`, `DownloadsView`, `UserPlaylistDetailView`, …):
/// `DependencyContainer.current` is only ever populated by `AppComposition`
/// at real app launch, so a preview canvas would hit `resolve()`'s own
/// `preconditionFailure("No registration for …")` rather than render.
///
/// A human should wire an entry point once `DownloadsView.swift`/
/// `AppShellView.swift` are free to edit again (both are off-limits
/// mid-edit by a concurrent workflow as of this screen's own addition):
/// add `case storageSettings` to `AppRoute`, a `StorageSettingsView()` case
/// in `AppShellView`'s route-to-view switch (the same switch that already
/// maps `.downloads(type:)` to `DownloadsView(type:)`), and a toolbar
/// button in `DownloadsView`'s `.toolbar` — e.g.
/// `ToolbarItem(placement: .secondaryAction) { Button("Storage") { coordinator.push(.storageSettings) } }`
/// — matching how `UserPlaylistDetailView`'s own toolbar pushes
/// `.createPlaylist(...)` via `coordinator.push`.
struct StorageSettingsView: View {
    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()
    @State private var isDeleteAllConfirmationPresented = false

    @Environment(\.appTheme) private var theme

    /// `.file` (powers-of-1000, "GB"/"MB") — the iOS system convention for
    /// on-disk storage sizes, matching what Settings > iPhone Storage itself
    /// uses. `.binary` is for in-memory sizes, not disk usage.
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var completedDownloadsCount: Int {
        downloadEngine.tasks.values.filter { $0.state == .completed }.count
    }

    private var totalStorageUsedText: String {
        Self.byteCountFormatter.string(fromByteCount: downloadEngine.totalBytesUsed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                statsCard
                deleteAllButton
            }
            .padding(Spacing.md)
            // Native-only tablet/Mac adaptation: settings keep to a readable column.
            .readableContentWidth()
        }
        .background(theme.color(.backgroundPrimary))
        .navigationTitle("Storage")
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

    // MARK: - Stats

    private var statsCard: some View {
        GlassSurface(.regular, cornerRadius: Radius.xl) {
            VStack(spacing: Spacing.md) {
                statRow(title: "Storage Used", value: totalStorageUsedText)
                statRow(title: "Downloaded Songs", value: "\(completedDownloadsCount)")
            }
            .padding(Spacing.md)
        }
    }

    private func statRow(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
            Spacer(minLength: Spacing.md)
            Text(value)
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
        }
    }

    // MARK: - Delete all

    /// Disabled on an empty catalog rather than `completedDownloadsCount ==
    /// 0` specifically — `deleteAll()` also tears down in-flight
    /// `.queued`/`.downloading`/`.paused` transfers, not just completed
    /// files, matching the same `!downloadEngine.tasks.isEmpty` guard
    /// `DownloadsView`'s own "Delete All" toolbar button already uses.
    private var deleteAllButton: some View {
        Button {
            isDeleteAllConfirmationPresented = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                theme.icon(.trash, size: 18)
                Text("Delete All Downloads")
                    .typography(Typography.titleSmall)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.color(.statusError))
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
        }
        .buttonStyle(.plain)
        .disabled(downloadEngine.tasks.isEmpty)
        .opacity(downloadEngine.tasks.isEmpty ? 0.5 : 1)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(theme.color(.statusError).opacity(0.4), lineWidth: 1)
        }
    }
}
