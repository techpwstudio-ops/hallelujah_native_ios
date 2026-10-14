import SwiftUI

/// Ports `SettingsPage` (`lib/views/settings_screen.dart`): a plain grouped
/// list of account/preference/app/support rows, no view model — every row
/// either reads an already-cached value (`CurrentUserStore`,
/// `AudioQualitySelector`, `KeyValueStoring`) or fires a single navigation/
/// side-effect call, the same posture `StorageSettingsView` (T47) already
/// established for a settings-shaped screen with nothing worth a view model.
///
/// DELIBERATE SCOPE CUTS (grounded against the real Dart screen):
/// 1. "Manage Family Members" (T63) is now a row below, gated on
///    `showsManageFamilyMembersRow` — Dart's own gate minus the
///    `SettingsService.instance.showSubscription` remote flag, matching the
///    "Subscription" row's (T61) own precedent of omitting that flag.
/// 2. No "Verse of Day" hide/unhide toggle — Dart's row only renders while
///    `VerseOfDayHistoryBloc`'s `isHiddenToday` is true
///    (`settings_screen.dart:261-278`), a home-screen feature not yet ported
///    natively; it's conditional chrome, not an always-present settings
///    fixture, so there's nothing to port until that bloc exists.
/// 3. No premium-upsell banner — the "Listen Without Distractions" card at
///    the top of Dart's screen (`settings_screen.dart:67-153`) is gated on
///    the same `showSubscription`/`isOwner`/`isPremiumUser` state as item 1,
///    for the same missing-subscription-infra reason.
/// 4. No "Delete Account" row anywhere on this screen — matches the real
///    Dart screen exactly (`settings_screen.dart` itself has no such row
///    either). Account deletion lives one tap further inside Help & Support
///    (`lib/views/support/dashboard.dart` -> `lib/views/support/
///    delete_account.dart`), which is T71 (Support)'s job, not this
///    screen's — this screen only links to Help & Support, below.
///
/// Two further, narrower deviations from a literal port, both explained at
/// their call sites: Dart's "Security" heading (Help & Support + Logout,
/// `settings_screen.dart:310`) is folded into a "Support" heading here per
/// this task's brief, and a "Notifications" row is added under Preferences
/// even though Dart's screen has no such row — routed to the already-
/// existing `.notificationSettings` `AppRoute` case per this task's brief,
/// ahead of the screen T66 is building to receive that push.
struct SettingsView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    @State private var authRepository: any AuthRepository = DependencyContainer.current.resolve()
    @State private var currentUserStore: CurrentUserStore = DependencyContainer.current.resolve()
    @State private var keyValueStore: any KeyValueStoring = DependencyContainer.current.resolve()
    @State private var membershipStore: MembershipStore = DependencyContainer.current.resolve()
    @State private var premiumGate: PremiumGate = DependencyContainer.current.resolve()

    @State private var user: User?
    @State private var membership: Membership?
    @State private var isPremium = false
    @State private var selectedAudioQuality: AudioQuality = .standard
    @State private var isDownloadOverWifiOnly = false
    @State private var isAudioQualityPickerPresented = false
    @State private var isLogoutConfirmationPresented = false

    /// `StorageService`'s key literal (`settings_screen.dart:248-249`),
    /// ported as-is — no native downloader reads it yet (T46/T47 gap), same
    /// "write now, read later" shape `AudioQualitySelector`'s own doc
    /// comment already uses for its key.
    private static let downloadOverWifiOnlyKey = "download_wifi_only"

    /// Constructed directly, not resolved from the container (it isn't
    /// registered as its own type) — the exact shape `AppComposition`
    /// itself uses for `PlaybackAnalyticsRecorder`'s own
    /// `AudioQualitySelector`. A stored `@State`, built exactly once per
    /// screen visit — deliberately NOT a computed property recomputed on
    /// every access: `NWPathConnectivityTypeProvider.init()` starts a real
    /// `NWPathMonitor` on a freshly spun-up dedicated queue as a side effect
    /// of construction alone (see that type's own file), so rebuilding this
    /// on every `userSelectedQuality`/`setUserSelectedQuality` call would
    /// leak one more live, never-cancelled path monitor per access.
    @State private var audioQualitySelector = AudioQualitySelector(
        keyValueStore: DependencyContainer.current.resolve(),
        batteryMonitor: UIDeviceBatteryLevelMonitor(),
        connectivityType: NWPathConnectivityTypeProvider()
    )

    private var downloadOverWifiOnlyBinding: Binding<Bool> {
        Binding(
            get: { isDownloadOverWifiOnly },
            set: { newValue in
                isDownloadOverWifiOnly = newValue
                keyValueStore.setBool(newValue, forKey: Self.downloadOverWifiOnlyKey)
            }
        )
    }

    private var contentLanguagesSubtitle: String {
        guard let languages = user?.languages, !languages.isEmpty else { return "Not set" }
        return languages.replacingOccurrences(of: ",", with: ", ")
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "-"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "-"
        return "\(shortVersion) (\(buildNumber))"
    }

    private var logoutSubtitle: String {
        let identity = user?.name ?? user?.mobile ?? user?.email ?? "—"
        return "You're logged in as \(identity)"
    }

    /// Scope cut #1's own gating logic (`settings_screen.dart:170-198`:
    /// `showSubscription && isPremiumUser && isOwner && maxMembers > 1`),
    /// minus the `showSubscription` remote flag — the existing "Subscription"
    /// row above omits it too (T61), so this follows that same native
    /// precedent rather than reintroducing the flag for just this one row.
    private var showsManageFamilyMembersRow: Bool {
        guard let membership else { return false }
        return membership.isOwner && membership.subscription.isActive && membership.subscription.maxMembers > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                section("Account") {
                    row(icon: "person.crop.circle", title: "Profile", subtitle: "View your profile page.") {
                        coordinator.push(.profile)
                    }
                    row(icon: "creditcard", title: "Subscription", subtitle: "Manage your plan.") {
                        coordinator.push(.subscriptionPlans)
                    }
                    if showsManageFamilyMembersRow {
                        rowDivider
                        row(icon: "person.2", title: "Manage Family Members") {
                            coordinator.push(.manageFamilyMembers)
                        }
                    }
                }

                section("Preferences") {
                    row(
                        icon: "globe",
                        title: "Content Languages",
                        subtitle: contentLanguagesSubtitle
                    ) {
                        coordinator.push(.contentLanguage(label: "Choose Content Language", canPop: true))
                    }
                    // T65 — shown to premium listeners only; Dart hides the
                    // row for everyone else (`settings_screen.dart`).
                    if isPremium {
                        rowDivider
                        row(
                            icon: "waveform",
                            title: "Audio Quality",
                            subtitle: selectedAudioQuality.settingsLabel
                        ) {
                            isAudioQualityPickerPresented = true
                        }
                    }
                    rowDivider
                    SettingsRow(
                        icon: "wifi",
                        title: "Download Over Wi-Fi Only",
                        trailing: .toggle(downloadOverWifiOnlyBinding)
                    )
                    rowDivider
                    row(icon: "bell", title: "Notifications") {
                        coordinator.push(.notificationSettings)
                    }
                    rowDivider
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        SettingsRow(icon: "externaldrive", title: "Storage")
                    }
                    .buttonStyle(.plain)
                }

                section("App & Terms") {
                    SettingsRow(icon: "info.circle", title: "Version", trailing: .value(versionText))
                    rowDivider
                    row(icon: "hand.raised", title: "Privacy Policy") {
                        UIApplication.shared.open(AppConfiguration.current.privacyPolicyURL)
                    }
                    rowDivider
                    row(icon: "doc.text", title: "Terms And Conditions") {
                        UIApplication.shared.open(AppConfiguration.current.termsAndConditionsURL)
                    }
                }

                section("Support") {
                    row(icon: "questionmark.circle", title: "Help & Support") {
                        coordinator.push(.helpSupportDashboard)
                    }
                    rowDivider
                    row(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Log Out",
                        subtitle: logoutSubtitle,
                        isDestructive: true
                    ) {
                        isLogoutConfirmationPresented = true
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
        .navigationTitle("Settings")
        .task {
            user = await currentUserStore.user
            membership = await membershipStore.membership
            isPremium = await premiumGate.hasPremium
            selectedAudioQuality = await audioQualitySelector.userSelectedQuality
            isDownloadOverWifiOnly = keyValueStore.bool(forKey: Self.downloadOverWifiOnlyKey)
        }
        .confirmationDialog("Audio Quality", isPresented: $isAudioQualityPickerPresented, titleVisibility: .visible) {
            ForEach(AudioQuality.allCases, id: \.rawValue) { quality in
                Button(quality.settingsLabel) {
                    audioQualitySelector.setUserSelectedQuality(quality)
                    selectedAudioQuality = quality
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Are you sure you want to log out?",
            isPresented: $isLogoutConfirmationPresented,
            titleVisibility: .visible
        ) {
            // `logout()` already triggers `session.logout()` +
            // `currentUserStore.clear()` internally, which in turn fires
            // `AppComposition`'s registered `session.setOnLogout` closure
            // (`SignOutSignal.notify()` + downloads teardown) — calling
            // anything else here would duplicate work it already does.
            Button("Log Out", role: .destructive) {
                Task { await authRepository.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Section / row helpers

    private func section<Content: View>(_ heading: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(heading)
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textSecondary))
                .padding(.horizontal, Spacing.xs)

            GlassSurface(.regular, cornerRadius: Radius.xl) {
                VStack(spacing: 0) {
                    rows()
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    private func row(
        icon: String,
        title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsRow(icon: icon, title: title, subtitle: subtitle, isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(theme.color(.separator))
    }
}

// MARK: - Row

/// One settings row: leading SF Symbol (no `IconToken` case exists for a
/// gear/person/bell/document/logout vocabulary, so this uses raw
/// `Image(systemName:)` per this task's brief), title/subtitle, and a
/// trailing chevron, value label, or toggle.
private struct SettingsRow: View {
    enum Trailing {
        case chevron
        case value(String)
        case toggle(Binding<Bool>)
        case none
    }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    var trailing: Trailing = .chevron

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: Spacing.lg)
                .foregroundStyle(isDestructive ? theme.color(.statusError) : theme.color(.textSecondary))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .typography(Typography.bodyLarge)
                    .foregroundStyle(isDestructive ? theme.color(.statusError) : theme.color(.textPrimary))
                if let subtitle {
                    Text(subtitle)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                }
            }

            Spacer(minLength: Spacing.sm)

            trailingView
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.color(.textTertiary))
        case .value(let text):
            Text(text)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
        case .toggle(let isOn):
            AppToggle(isOn: isOn)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Audio quality labels

/// `session.dart`'s `selectedAudioQualityLabel` (lines 432-440), ported
/// verbatim. Scoped `fileprivate` to this screen rather than added to
/// `AudioQuality.swift` itself — this task's brief scopes it to creating one
/// new file, and no other screen needs this label yet.
private extension AudioQuality {
    var settingsLabel: String {
        switch self {
        case .low: "Data Saver"
        case .standard: "Standard"
        case .high: "High Quality"
        }
    }
}
