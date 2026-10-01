import SwiftUI

/// T66 — ports `NotificationSettingsPage`
/// (`lib/views/notification_settings_page.dart`): a "Daily Bible" card with
/// one switch, an "Updates" card with one switch per eligible topic (or the
/// empty-state line when there are none), and a grey footnote below both.
///
/// Styling modeled on `StorageSettingsView` (`GlassSurface` cards in a
/// `ScrollView`/`VStack`, no explicit `init`) and the loading/empty/error
/// state machine on `UserPlaylistDetailView`/`UserPlaylistDetailViewModel`
/// (`LoadState` switch, `.task { loadIfNeeded() }`, `.refreshable`).
///
/// No required init parameters, matching `AppRoute.notificationSettings`
/// carrying no payload — wiring the route to this view in
/// `AppShellView`'s switch is a deferred patch (that file was off-limits to
/// this track), so this type's name and no-arg construction are exactly
/// what that one-line `case` addition needs.
struct NotificationSettingsView: View {
    @State private var viewModel = NotificationSettingsViewModel()

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch viewModel.state {
                case .loading:
                    LoadingStateView()
                case .failed:
                    ErrorStateView(
                        title: "Couldn't load notification settings",
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                case .loaded(let topics):
                    bibleSection
                    updatesSection(topics: topics)
                    footnote
                case .empty:
                    bibleSection
                    updatesEmptySection
                    footnote
                }
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
        .navigationTitle("Notifications")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.loadIfNeeded() }
    }

    // MARK: - Daily Bible

    private var bibleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Daily Bible")
            GlassSurface(.regular, cornerRadius: Radius.xl) {
                row(
                    title: "Verse of the Day",
                    subtitle: "One verse each day, in your Bible language.",
                    isOn: viewModel.bibleNotificationsEnabled,
                    isBusy: viewModel.isBibleBusy,
                    onToggle: { newValue in Task { await viewModel.toggleBible(newValue) } }
                )
                .padding(Spacing.md)
            }
        }
    }

    // MARK: - Updates

    private func updatesSection(topics: [NotificationTopic]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Updates")
            GlassSurface(.regular, cornerRadius: Radius.xl) {
                VStack(spacing: Spacing.md) {
                    ForEach(topics) { topic in
                        row(
                            title: topic.name,
                            subtitle: subtitle(for: topic),
                            isOn: viewModel.isEnabled(topic.topicKey),
                            isBusy: viewModel.isBusy(topic.topicKey),
                            onToggle: { newValue in
                                Task { await viewModel.toggleTopic(topic.topicKey, enabled: newValue) }
                            }
                        )
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    private var updatesEmptySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Updates")
            Text("No update channels are available yet.")
                .typography(Typography.bodySmall)
                .foregroundStyle(theme.color(.textSecondary))
                .padding(.vertical, Spacing.md)
        }
    }

    /// `_topicSubtitle` (ibid.): a topic scoped to a language reads "In
    /// {language}.", an unscoped (global) one reads "Announcements for
    /// everyone."
    private func subtitle(for topic: NotificationTopic) -> String {
        guard let language = topic.language?.trimmingCharacters(in: .whitespaces), !language.isEmpty else {
            return "Announcements for everyone."
        }
        return "In \(language)."
    }

    // MARK: - Shared row

    /// `_switchTile` (ibid.): title/subtitle on the leading side, either the
    /// switch or — while that row's own toggle is in flight — a small
    /// spinner in its place, trailing.
    private func row(
        title: String,
        subtitle: String,
        isOn: Bool,
        isBusy: Bool,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            Spacer(minLength: Spacing.md)
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                AppToggle(isOn: Binding(get: { isOn }, set: onToggle))
            }
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(
            "Turning a channel off stops new notifications from it. Alerts about your account "
                + "and anything you asked us to send you are not affected."
        )
        .typography(Typography.bodySmall)
        .foregroundStyle(theme.color(.textSecondary))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .typography(Typography.titleSmall)
            .foregroundStyle(theme.color(.textSecondary))
    }
}
