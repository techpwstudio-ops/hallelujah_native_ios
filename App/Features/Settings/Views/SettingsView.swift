import SwiftUI

/// Ports `SettingsPage` (`lib/views/settings_screen.dart`) 1:1: black scaffold,
/// 12pt horizontal / 8pt vertical padding, optional premium upsell banner,
/// flat `SettingsListItem` rows under `CustomHeading`s. The "Notifications"
/// and "Storage" rows the earlier native cut added are gone: Flutter's
/// settings screen has neither (notification settings is reachable only via
/// its route). Icons are SF Symbol stand-ins for the Flutter SVG assets
/// (see report for the asset list).
struct SettingsView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    @State private var authRepository: any AuthRepository = DependencyContainer.current.resolve()
    @State private var currentUserStore: CurrentUserStore = DependencyContainer.current.resolve()
    @State private var keyValueStore: any KeyValueStoring = DependencyContainer.current.resolve()
    @State private var membershipStore: MembershipStore = DependencyContainer.current.resolve()
    @State private var premiumGate: PremiumGate = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()

    @State private var user: User?
    @State private var membership: Membership?
    @State private var isPremium = false
    @State private var selectedAudioQuality: AudioQuality = .standard
    @State private var isDownloadOverWifiOnly = false
    @State private var isAudioQualityPickerPresented = false
    @State private var isLogoutConfirmationPresented = false
    @State private var isVerseOfDayHidden = false

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

    private var contentLanguagesSubtitle: Text {
        guard let languages = user?.languages, !languages.isEmpty else { return Text("Not set") }
        return Text(verbatim: languages.replacingOccurrences(of: ",", with: ", "))
    }

    private var logoutSubtitle: Text {
        let identity = user?.name ?? user?.mobile ?? user?.email ?? "-"
        return Text("You are logged in as \(identity).")
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

    private var versionText: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "-"
    }

    private var showSubscription: Bool { RemoteSettings.current.showSubscription }
    private var isOwner: Bool { membership?.isOwner != false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showSubscription && isOwner && !isPremium {
                    upsellBanner
                }
                Spacer().frame(height: Dimens.verticalSpacing)
                ParityHeading(text: "Account")
                tile(icon: "asset:profile", title: "Profile", subtitle: Text("View your profile page.")) {
                    coordinator.push(.profile)
                }
                if showSubscription {
                    tile(icon: "asset:manage_subscription", title: "Manage Subscription", subtitle: Text("Manage subscription plans")) {
                        coordinator.push(.subscriptionPlans)
                    }
                    if isPremium && isOwner && showsManageFamilyMembersRow {
                        tile(icon: "asset:manage_members", title: "Manage Family Members", subtitle: Text("Manage upto 4 family members")) {
                            coordinator.push(.manageFamilyMembers)
                        }
                    }
                }

                Spacer().frame(height: Dimens.dividerSpacing)
                ParityHeading(text: "Preferences")
                tile(icon: "asset:settings_content_lang", title: "Content Languages", subtitle: contentLanguagesSubtitle) {
                    coordinator.push(.contentLanguage(label: "Choose Content Language", canPop: true))
                }
                tile(icon: "character.bubble", title: "App Language", subtitle: Text(verbatim: AppLanguageStore.shared.selected.nativeName)) {
                    coordinator.push(.appLanguage)
                }
                if isPremium || !showSubscription {
                    tile(
                        icon: "asset:audio_quality",
                        title: "Audio Quality",
                        subtitle: Text(verbatim: String(localized: "Selected audio quality is \(selectedAudioQuality.settingsLabel.localizedLowercase)"))
                    ) {
                        isAudioQualityPickerPresented = true
                    }
                }
                ParityListTile(
                    title: "Download Over Wi-Fi Only",
                    subtitle: Text("If switched on, we will download content only with a Wi-Fi network"),
                    leading: { leadingIcon("asset:settings_download_icon") },
                    trailing: { AppToggle(isOn: downloadOverWifiOnlyBinding) }
                )
                if isVerseOfDayHidden {
                    ParityListTile(
                        title: "Verse of Day",
                        subtitle: Text("Hidden for today. Toggle to show."),
                        leading: { leadingIcon("book") },
                        trailing: { AppToggle(isOn: verseOfDayBinding) }
                    )
                }

                Spacer().frame(height: Dimens.dividerSpacing)
                ParityHeading(text: "App & Terms")
                ParityListTile(
                    title: "Version",
                    subtitle: Text(verbatim: versionText),
                    leading: {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    },
                    trailing: { EmptyView() }
                )
                tile(icon: "asset:settings_privacy_policy", title: "Privacy Policy", subtitle: Text("Your data, your rights.")) {
                    UIApplication.shared.open(AppConfiguration.current.privacyPolicyURL)
                }
                tile(icon: "asset:settings_terms_condition", title: "Terms And Conditions", subtitle: Text("All the details you need to know.")) {
                    UIApplication.shared.open(AppConfiguration.current.termsAndConditionsURL)
                }

                Spacer().frame(height: Dimens.dividerSpacing)
                ParityHeading(text: "Security")
                tile(icon: "asset:settings_help_support", title: "Help & Support", subtitle: Text("For more info on support")) {
                    coordinator.push(.helpSupportDashboard)
                }
                tile(icon: "asset:settings_logout", title: "Logout", subtitle: logoutSubtitle) {
                    isLogoutConfirmationPresented = true
                }
                if AppConfiguration.current.environment != .production {
                    HStack {
                        Spacer()
                        ParityHeading(text: "You are tester")
                            .fixedSize()
                        Spacer()
                    }
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, Dimens.screenPaddingAll)
            .padding(.horizontal, Dimens.screenPaddingAll * 1.5)
        }
        .parityScaffold()
        .parityNavTitle("Settings", leading: true)
        .task {
            user = await currentUserStore.user
            membership = await membershipStore.membership
            isPremium = await premiumGate.hasPremium
            selectedAudioQuality = await audioQualitySelector.userSelectedQuality
            isDownloadOverWifiOnly = keyValueStore.bool(forKey: Self.downloadOverWifiOnlyKey)
            isVerseOfDayHidden = VerseOfDayLocalStore(keyValueStore: keyValueStore).isHiddenToday
        }
        .parityFitSheet(isPresented: $isAudioQualityPickerPresented) {
            AudioQualitySheet(selected: selectedAudioQuality) { quality in
                let changed = quality != selectedAudioQuality
                audioQualitySelector.setUserSelectedQuality(quality)
                selectedAudioQuality = quality
                isAudioQualityPickerPresented = false
                // `changeAudioQuality`'s `reloadSourcesAtCurrentPosition()`:
                // what's already playing switches to the new quality now.
                if changed {
                    Task { await audioEngine.reloadSourcesAtCurrentPosition() }
                }
            }
        }
        .parityConfirmationDialog(
            isPresented: $isLogoutConfirmationPresented,
            message: "Are you sure to logout Hallelujah?"
        ) {
            // `logout()` already runs the full sign-out chain internally.
            Task { await authRepository.logout() }
        }
    }

    private var verseOfDayBinding: Binding<Bool> {
        Binding(
            get: { false },
            set: { _ in
                VerseOfDayLocalStore(keyValueStore: keyValueStore).unhide()
                isVerseOfDayHidden = false
            }
        )
    }

    // MARK: - Pieces

    private func leadingIcon(_ systemName: String) -> some View {
        GlyphImage(name: systemName, size: 24)
            .foregroundStyle(AccountParity.white)
            .frame(width: 24, height: 24)
    }

    private func tile(icon: String, title: LocalizedStringKey, subtitle: Text, action: @escaping () -> Void) -> some View {
        ParityListTile(
            title: title,
            subtitle: subtitle,
            onTap: action,
            leading: { leadingIcon(icon) },
            trailing: { ParityArrowNext() }
        )
    }

    /// "Listen Without Distractions" card: 180pt, 12pt radius, 1pt border,
    /// 0.2 -> 0.75 black gradient, content pinned 12pt from the bottom.
    private var upsellBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("Listen Without Distractions")
                    .font(AccountParity.font(24, .bold))
                    .foregroundStyle(AccountParity.white)
                Spacer().frame(height: 8)
                Text("Upgrade to Premium for ad-free worship, high-quality audio, and offline listening.")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white)
                    .multilineTextAlignment(.leading)
                Spacer().frame(height: 20)
                ParityFilledButton(title: "Try Free For 1 Month") {
                    coordinator.push(.subscriptionPlans)
                }
            }
            .padding(12)
        }
        .frame(height: 180)
        .background(AccountParity.black)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(AccountParity.border, lineWidth: Dimens.borderWidth)
        )
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
        case .low: String(localized: "Data Saver")
        case .standard: String(localized: "Standard")
        case .high: String(localized: "High Quality")
        }
    }
}
