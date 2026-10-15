import SwiftUI

/// T66 — ports `NotificationSettingsPage`
/// (`lib/views/notification_settings_page.dart`) with Flutter metrics: black
/// scaffold, 16pt side padding, `CustomHeading`s, `SwitchListTile.adaptive`
/// rows (zero content padding, 17/w600 title, grey subtitle, 20pt spinner as
/// the leading widget while a row is busy) and a 12pt grey footnote.
/// Loading / failed states are native additions (Flutter reads the topic
/// list synchronously from memory).

struct NotificationSettingsView: View {
    @State private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.state {
                case .loading:
                    LoadingStateView()
                case .failed:
                    ErrorStateView(
                        title: "Couldn't load notification settings",
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                case .loaded(let topics):
                    content(topics: topics)
                case .empty:
                    content(topics: [])
                }
            }
            .padding(.horizontal, 16)
        }
        .parityScaffold()
        .parityNavTitle("Notifications")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private func content(topics: [NotificationTopic]) -> some View {
        Spacer().frame(height: 8)
        ParityHeading(text: "Daily Bible")
        row(
            title: "Verse of the Day",
            subtitle: "One verse each day, in your Bible language.",
            isOn: viewModel.bibleNotificationsEnabled,
            isBusy: viewModel.isBibleBusy,
            onToggle: { newValue in Task { await viewModel.toggleBible(newValue) } }
        )
        Spacer().frame(height: 16)
        ParityHeading(text: "Updates")
        if topics.isEmpty {
            Text("No update channels are available yet.")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.grey)
                .padding(.vertical, 20)
        } else {
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
        Spacer().frame(height: 24)
        Text(
            "Turning a channel off stops new notifications from it. Alerts about your account "
                + "and anything you asked us to send you are not affected."
        )
        .font(AccountParity.bodySmall)
        .lineSpacing(12 * 0.5)
        .foregroundStyle(AccountParity.grey)
        Spacer().frame(height: 16)
    }

    /// `_topicSubtitle`.
    private func subtitle(for topic: NotificationTopic) -> String {
        guard let language = topic.language?.trimmingCharacters(in: .whitespaces), !language.isEmpty else {
            return "Announcements for everyone."
        }
        return "In \(language)."
    }

    /// `_switchTile` (`SwitchListTile.adaptive`).
    private func row(
        title: String,
        subtitle: String,
        isOn: Bool,
        isBusy: Bool,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 16) {
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(AccountParity.white)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AccountParity.font(17, .semibold))
                    .foregroundStyle(AccountParity.white)
                Text(subtitle)
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.grey)
            }
            Spacer(minLength: 8)
            AppToggle(isOn: Binding(get: { isOn }, set: onToggle), enabled: !isBusy)
        }
        .frame(minHeight: 72)
    }
}
