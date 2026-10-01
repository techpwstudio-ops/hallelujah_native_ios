import SwiftUI

/// Ported from `AccountSetupPage` (`lib/views/auth/account_setup_page.dart`)
/// — the two-step "who they are, then what they want to listen to" flow a
/// new/incomplete account is routed to straight after sign-in
/// (`RootView`'s `.accountSetup` case).
///
/// The languages step (T25, `LanguageViewModel`/`LanguageGridView`/
/// `LanguageSelectionSummaryView`) is the real `ContentLanguageUi` port —
/// not the placeholder this file originally shipped with (T24) pending this
/// task. Its bottom action is `LanguageSelectionSummaryView`'s own gradient
/// button, not the shared `AppButton` the details step uses below — Dart
/// itself splits these two (`_ContinueButton` vs. the summary's own, see
/// `account_setup_page.dart`'s `_ContinueButton` doc comment), so `body`
/// swaps which one is shown per step rather than routing both through one
/// button.
///
/// Two deliberate departures from a literal port, both grounded in the Dart
/// source rather than guessed:
///
/// - **No profile-image UI.** T24's own roadmap bullet ("image picker,
///   crop/compress, S3 upload") doesn't match this screen: `AccountSetupPage`
///   collects only name/date-of-birth/gender, then languages — no image
///   anywhere. The real avatar-upload UI (`UploadPhoto`, `CropCompressImagePage`)
///   lives on the separate `/profile` screen (`ProfilePage`), which
///   progress.md's own **T70 — Profile and settings** already claims via its
///   Done criterion ("parity with `lib/views/profile/**`"). Building that
///   pipeline here would be infrastructure with no on-screen consumer until
///   T70 anyway, so it's left for that task rather than invented early.
/// - **No back-navigation/logout-confirmation chrome.** Dart reaches this
///   screen via `NavigationService.offAll(AccountSetupPage.routeName)` (both
///   from `AuthenticationPage._navigateToNextScreen` and from
///   `FlashScreen._resolveDestination`), which replaces the whole nav stack —
///   confirmed by grepping every call site. With nothing beneath it,
///   `Navigator.canPop(context)` is false, so Flutter never renders an
///   automatic back chevron here, and iOS's interactive edge-swipe (which
///   itself requires a poppable route to swipe back to) never engages either.
///   `PopScope`'s `onPopInvokedWithResult` — the "Are you sure back? You will
///   be logged out" dialog, and the language-step's "back to details" step —
///   is therefore reachable on Android (a hardware/gesture back press always
///   attempts a pop, poppable or not) but dead code on Dart's own iOS build.
///   Matching that real iOS behavior means building neither here, the same
///   "match what the reference app actually does on this platform, not what
///   its cross-platform code merely contains" call already made for
///   `fallbackChannel` (T21).
struct AccountSetupView: View {
    let onComplete: () -> Void

    @State private var viewModel = AccountSetupViewModel()
    @State private var languageViewModel = LanguageViewModel()
    @State private var step: Step = .details
    @State private var isAppleProvider = false
    @State private var cachedUser: User?

    @State private var fName = ""
    @State private var lName = ""
    @State private var fNameError: String?
    @State private var lNameError: String?

    @State private var dateOfBirth: Date?
    @State private var isDatePickerPresented = false
    @State private var pickerDate = Self.maximumBirthDate

    @State private var gender: String?

    @Environment(\.toastCenter) private var toastCenter
    @FocusState private var focusedField: Field?

    private enum Step: Equatable { case details, languages }
    /// `@FocusState`'s value type must be `Hashable` — needs the explicit
    /// conformance below since Swift only synthesizes it when declared.
    private enum Field: Hashable { case fName, lName }

    /// `DateTime(1900)` / `DateTime.now().subtract(Duration(days: 13 * 365))`
    /// — `dateInput`'s own `firstDate`/`lastDate` bounds in `_DetailsStep`,
    /// which already keep the picker from offering an under-13 date; the
    /// `_submitDetails` age check below is kept anyway purely for parity,
    /// same as Dart having both.
    private static let minimumBirthDate = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    private static let maximumBirthDate = Calendar.current.date(byAdding: .day, value: -(13 * 365), to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            if step == .languages {
                languagesHeader
            }

            ScrollView {
                Group {
                    if step == .languages {
                        languagesStep
                    } else {
                        detailsStep
                    }
                }
                .padding(Spacing.sm)
            }

            if step == .languages {
                LanguageSelectionSummaryView(
                    viewModel: languageViewModel,
                    onContinue: { Task { await finishLanguages() } }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            } else {
                AppButton(
                    label: "Continue",
                    action: { Task { await submit() } },
                    isLoading: viewModel.state == .loading
                )
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
        }
        .background(AuthColors.background.ignoresSafeArea())
        .toastOverlay()
        .task { await loadCachedUser() }
        .appSheet(isPresented: $isDatePickerPresented, detents: [.height(340)]) { datePickerContent }
        .onChange(of: viewModel.state) { _, newValue in
            switch newValue {
            case .success:
                step = .languages
            case let .error(message):
                toastCenter.show(message)
            case .idle, .loading:
                break
            }
        }
    }

    // MARK: Languages step

    /// The page-title-plus-Reset-action AppBar Dart shows only on this step
    /// (`account_setup_page.dart`'s `AppBar.title`/`actions`) — inline here
    /// since this screen has no navigation bar chrome of its own.
    private var languagesHeader: some View {
        HStack {
            Spacer()
            Text("Choose Your Languages")
                .typography(Typography.titleMedium)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button("Reset") { languageViewModel.reset() }
                .typography(Typography.bodyMedium)
                .foregroundStyle(languageViewModel.hasSelection ? AuthColors.secondaryText : AuthColors.white24)
                .disabled(!languageViewModel.hasSelection)
                .padding(.trailing, Spacing.md)
        }
        .padding(.vertical, Spacing.sm)
    }

    /// `ContentLanguageUi` (`read_language.dart`) — the scrollable half only;
    /// the pinned summary/action is `LanguageSelectionSummaryView` in `body`.
    /// `.task` fires `initialize()` fresh each time this view mounts, same
    /// as Dart's `initState()` re-running on every remount of the widget
    /// (`_step` flipping to `.languages` always creates a new
    /// `ContentLanguageUi` instance in Dart too, not a reused one).
    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select the languages you love listening to")
                .typography(Typography.bodyMedium)
                .foregroundStyle(AuthColors.tertiaryText)

            RuleBannerView()

            if languageViewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxl)
            } else if let errorMessage = languageViewModel.errorMessage {
                VStack(spacing: Spacing.md) {
                    Text(errorMessage)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await languageViewModel.fetchLanguages() } }
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
            } else {
                LanguageGridView(
                    languageOptions: languageViewModel.languageOptions,
                    isSelected: languageViewModel.isSelected,
                    isPrimary: languageViewModel.isPrimary,
                    canToggle: languageViewModel.canToggle,
                    onTap: toggleLanguage
                )
            }
        }
        .task { await languageViewModel.initialize() }
    }

    // MARK: Details step

    private var detailsStep: some View {
        VStack(spacing: 0) {
            Text("Tell us a little about you")
                .typography(Typography.headlineMedium)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: Spacing.xs)

            Text("This helps us personalize your listening experience..")
                .typography(Typography.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: Spacing.lg)

            if !isAppleProvider {
                nameField(
                    label: "First Name",
                    hint: "Enter First Name",
                    text: $fName,
                    error: fNameError,
                    field: .fName,
                    autofill: .givenName
                )

                Spacer().frame(height: Spacing.sm)

                nameField(
                    label: "Last Name",
                    hint: "Last Name",
                    text: $lName,
                    error: lNameError,
                    field: .lName,
                    autofill: .familyName
                )

                Spacer().frame(height: Spacing.sm)
            }

            dateField

            Spacer().frame(height: Spacing.sm)

            genderField
        }
    }

    private func nameField(
        label: String, hint: String, text: Binding<String>, error: String?,
        field: Field, autofill: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel(label)

            Spacer().frame(height: Spacing.xs)

            TextField("", text: text, prompt: Text(hint).foregroundStyle(AuthColors.hint))
                .textContentType(autofill)
                .textInputAutocapitalization(.words)
                .typography(Typography.bodyMedium)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .focused($focusedField, equals: field)
                .padding(.horizontal, Spacing.md)
                .frame(height: Spacing.inputHeight)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AuthColors.fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(AuthColors.textFieldFocusedBorder, lineWidth: 1)
                        .opacity(focusedField == field ? 1 : 0)
                }

            if let error {
                Text(error)
                    .typography(Typography.labelSmall)
                    .foregroundStyle(.red)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel("Date Of Birth")

            Spacer().frame(height: Spacing.xs)

            Button {
                focusedField = nil
                pickerDate = dateOfBirth ?? Self.maximumBirthDate
                isDatePickerPresented = true
            } label: {
                HStack {
                    Text(dateOfBirth.map(Self.displayFormatter.string(from:)) ?? "Enter Date Of Birth")
                        .typography(Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundStyle(dateOfBirth == nil ? AuthColors.hint : .white)
                    Spacer()
                    IconToken.calendar.image
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: Spacing.inputHeight)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AuthColors.fill)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// `_DatePickerSheet` (`custom_inputs.dart`) — `.appSheet` gives this the
    /// same glass chrome every other sheet in the app already uses rather
    /// than Dart's flat `bottomSheetBgColor` fill; sheets sit outside D10's
    /// pixel-parity scope (see `AppSheetContainer`'s own doc comment), the
    /// same reasoning `CountryPickerView` (T21) already relies on.
    private var datePickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { isDatePickerPresented = false }
                Spacer()
                Button("Done") {
                    dateOfBirth = pickerDate
                    isDatePickerPresented = false
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            DatePicker(
                "Date of Birth",
                selection: $pickerDate,
                in: Self.minimumBirthDate...Self.maximumBirthDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel("Gender")

            Spacer().frame(height: Spacing.xs)

            HStack(spacing: Spacing.lg) {
                genderOption(label: "Male", value: "male")
                genderOption(label: "Female", value: "female")
            }
        }
    }

    private func genderOption(label: String, value: String) -> some View {
        Button {
            gender = value
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: gender == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(.white)
                Text(label)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func requiredLabel(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .typography(Typography.titleSmall)
                .foregroundStyle(.white)
            Text(" * ")
                .typography(Typography.bodyMedium)
                .foregroundStyle(.red)
        }
    }

    // MARK: Actions

    private func loadCachedUser() async {
        guard let user = await viewModel.loadCachedUser() else { return }
        cachedUser = user
        isAppleProvider = user.isAppleProvider
        step = (user.currentStep ?? 1) >= 2 ? .languages : .details
        fName = user.firstName ?? ""
        lName = user.lastName ?? ""
        gender = user.gender
        dateOfBirth = user.dateOfBirth.flatMap(Self.parseDate)
    }

    /// `toggleLanguageWithLimit` — the notifier itself must not toast (see
    /// `LanguageViewModel.toggleLanguage`'s doc comment), so the refusal
    /// toast is surfaced from here.
    private func toggleLanguage(_ name: String) {
        guard !languageViewModel.toggleLanguage(name) else { return }
        toastCenter.show("You can select up to \(LanguageViewModel.maxSelectableLanguages) languages. Remove one to add another.")
    }

    /// `_finishLanguages` — saves the pick and enters the app.
    private func finishLanguages() async {
        guard await languageViewModel.saveLanguages() else {
            if case let .error(message) = languageViewModel.saveState {
                toastCenter.show(message)
            }
            return
        }
        onComplete()
    }

    /// `_submitDetails` — form validation first (inline field errors), then
    /// the three toast-surfaced checks in the same order Dart runs them.
    private func submit() async {
        guard viewModel.state != .loading else { return }

        fNameError = nil
        lNameError = nil
        if !isAppleProvider {
            fNameError = Self.validateName(fName, hint: "Enter First Name")
            lNameError = Self.validateName(lName, hint: "Last Name")
            guard fNameError == nil, lNameError == nil else { return }
        }

        guard let gender else {
            toastCenter.show("Please choose gender")
            return
        }
        guard let dateOfBirth else {
            toastCenter.show("Please choose date of birth")
            return
        }
        guard Date().timeIntervalSince(dateOfBirth) / 86_400 >= Double(13 * 365) else {
            toastCenter.show("Minimum age requirement is 13 years")
            return
        }

        focusedField = nil

        let trimmedFName = fName.trimmingCharacters(in: .whitespaces)
        let trimmedLName = lName.trimmingCharacters(in: .whitespaces)
        await viewModel.submitDetails(
            fName: isAppleProvider ? cachedUser?.firstName : (trimmedFName.isEmpty ? nil : trimmedFName),
            lName: isAppleProvider ? cachedUser?.lastName : (trimmedLName.isEmpty ? nil : trimmedLName),
            dateOfBirth: Self.isoFormatter.string(from: dateOfBirth),
            gender: gender
        )
    }

    private static func validateName(_ value: String, hint: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return hint }
        if trimmed.count < 2 { return "Please enter at least 2 characters." }
        return nil
    }

    /// `date.toIso8601String()` (`custom_inputs.dart`'s `dateInput`) on a
    /// local, non-UTC `DateTime` — no `Z`/offset suffix, so this writes and
    /// reads the same fixed local-time format rather than relying on
    /// `ISO8601DateFormatter`, which requires a timezone designator to parse.
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()

    /// `dd/MM/yyyy` — `dateInput`'s own `displayText` formatting.
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    /// Falls back through the fuller ISO8601 forms too: a `dateOfBirth`
    /// round-tripped through the server on `updateProfile`'s response could
    /// come back re-formatted with a UTC designator rather than in the exact
    /// local shape `isoFormatter` writes — same layered leniency
    /// `User.parseDate` already uses for `createdAt`/`updatedAt`. A miss just
    /// leaves the picker unset rather than failing to load the screen.
    private static func parseDate(_ string: String) -> Date? {
        if let date = isoFormatter.date(from: string) { return date }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

#Preview {
    AccountSetupView(onComplete: {})
}
