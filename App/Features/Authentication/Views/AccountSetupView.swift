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
            appBar

            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        if step == .languages {
                            languagesStep
                        } else {
                            detailsStep
                        }
                    }
                    .padding(Dimens.screenPaddingAll)
                }
                .scrollDismissesKeyboard(.interactively)

                Spacer().frame(height: Dimens.spacing12)

                if step == .languages {
                    LanguageSelectionSummaryView(
                        viewModel: languageViewModel,
                        onContinue: { Task { await finishLanguages() } }
                    )
                } else {
                    continueButton
                }
            }
            .padding(Dimens.screenPaddingAll)
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

    /// Empty `AppBar` (kToolbarHeight 56, black, centred title) on the details
    /// step; on the languages step it carries the title and the Reset action
    /// (`account_setup_page.dart`'s `AppBar.title`/`actions`).
    private var appBar: some View {
        ZStack {
            if step == .languages {
                Text("Choose Your Languages")
                    .typography(Typography.titleMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .overlay(alignment: .trailing) {
            if step == .languages {
                Button("Reset") { languageViewModel.reset() }
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(languageViewModel.hasSelection ? AuthColors.secondaryText : AuthColors.white24)
                    .disabled(!languageViewModel.hasSelection)
                    .padding(.horizontal, Dimens.spacing12)
            }
        }
    }

    /// `_ContinueButton`: white `MyContainer`, radius 8, 8pt padding around a
    /// `titleSmall` label coloured `colorScheme.surface` (0xFF1D1D1D).
    private var continueButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if viewModel.state == .loading {
                    MaterialSpinner(color: AuthColors.fill, size: 20, lineWidth: 2.5)
                } else {
                    Text("Continue")
                        .typography(Typography.titleSmall)
                        .foregroundStyle(AuthColors.fill)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Dimens.paddingSmall)
            .background {
                RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                    .fill(Color.white)
            }
        }
        .buttonStyle(.plain)
    }

    /// `ContentLanguageUi` (`read_language.dart`) — the scrollable half only;
    /// the pinned summary/action is `LanguageSelectionSummaryView` in `body`.
    /// `.task` fires `initialize()` fresh each time this view mounts, same
    /// as Dart's `initState()` re-running on every remount of the widget
    /// (`_step` flipping to `.languages` always creates a new
    /// `ContentLanguageUi` instance in Dart too, not a reused one).
    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select the languages you love listening to")
                .typography(Typography.bodyMedium)
                .foregroundStyle(AuthColors.tertiaryText)

            Spacer().frame(height: Dimens.spacing16)

            RuleBannerView()

            Spacer().frame(height: Dimens.spacing20)

            if languageViewModel.isLoading {
                MaterialSpinner(color: .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Dimens.spacing48)
            } else if let errorMessage = languageViewModel.errorMessage {
                VStack(spacing: Dimens.spacing16) {
                    Text(errorMessage)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await languageViewModel.fetchLanguages() } }
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Dimens.spacing48)
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
                .padding(.horizontal, Dimens.spacing12)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: Dimens.spacing4)

            Text("This helps us personalize your listening experience..")
                .typography(Typography.bodyMedium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: Dimens.spacing24)

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
            }

            Spacer().frame(height: Dimens.spacing8)

            dateField

            Spacer().frame(height: Dimens.spacing8)

            genderField
        }
    }

    private func nameField(
        label: LocalizedStringKey, hint: LocalizedStringKey, text: Binding<String>, error: String?,
        field: Field, autofill: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel(label, labelTypography: Typography.titleSmall)

            Spacer().frame(height: Dimens.spacing8)

            TextField("", text: text, prompt: Text(hint).font(Self.hintFont).foregroundStyle(AuthColors.hint))
                .textContentType(autofill)
                .textInputAutocapitalization(.words)
                .typography(Typography.bodyLarge)
                .foregroundStyle(.white)
                .focused($focusedField, equals: field)
                .padding(.horizontal, Dimens.spacing12)
                .frame(height: AuthMetrics.textFieldHeight)
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
                    .typography(Typography.bodySmall)
                    .foregroundStyle(AuthColors.error)
                    .padding(.top, Dimens.spacing8)
                    .padding(.leading, Dimens.spacing12)
            }
        }
        .padding(.vertical, Dimens.spacing2)
    }

    /// `bodySmall` + `w500`, the hint style in `custom_inputs.dart`.
    private static let hintFont = Font.custom(Typography.fontFamily, size: 12).weight(.medium)

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel("Date Of Birth", labelTypography: Typography.titleSmall)

            Spacer().frame(height: Dimens.spacing8)

            Button {
                focusedField = nil
                pickerDate = dateOfBirth ?? Self.maximumBirthDate
                isDatePickerPresented = true
            } label: {
                HStack {
                    (dateOfBirth.map { Text(verbatim: Self.displayFormatter.string(from: $0)) } ?? Text("Enter Date Of Birth"))
                        .typography(Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundStyle(dateOfBirth == nil ? AuthColors.hint : .white)
                    Spacer()
                    IconToken.calendar.image
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Dimens.spacing12)
                .padding(.vertical, Dimens.spacing16)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AuthColors.fill)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Dimens.spacing2)
    }

    /// `_DatePickerSheet` (`custom_inputs.dart`) — `.appSheet` gives this the
    /// same glass chrome every other sheet in the app already uses rather
    /// than Dart's flat `bottomSheetBgColor` fill; sheets sit outside D10's
    /// pixel-parity scope (see `AppSheetContainer`'s own doc comment), the
    /// same reasoning `CountryPickerView` (T21) already relies on.
    private var datePickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isDatePickerPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Button {
                    dateOfBirth = pickerDate
                    isDatePickerPresented = false
                } label: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Select")
            }
            .padding(.horizontal, Dimens.spacing8)
            .padding(.vertical, Dimens.spacing4)

            DatePicker(
                "Date of Birth",
                selection: $pickerDate,
                in: Self.minimumBirthDate...Self.maximumBirthDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 220)

            Spacer().frame(height: Dimens.spacing8)
        }
    }

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel("Gender", labelTypography: Typography.bodyMedium)

            HStack(spacing: 0) {
                genderOption(label: "Male", value: "male")
                genderOption(label: "Female", value: "female")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `Radio` (48pt tap target, 18pt circle, grey when active, `white60`
    /// outline otherwise) followed by the label.
    private func genderOption(label: LocalizedStringKey, value: String) -> some View {
        Button {
            gender = value
        } label: {
            HStack(spacing: 0) {
                Image(systemName: gender == value ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(gender == value ? Color.gray : Color.white.opacity(0.6))
                    .frame(width: 48, height: 48)
                Text(label)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func requiredLabel(_ text: LocalizedStringKey, labelTypography: TypographyToken) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .typography(labelTypography)
                .foregroundStyle(.white)
            Text(" * ")
                .typography(labelTypography)
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
        toastCenter.show(String(localized: "You can select up to \(LanguageViewModel.maxSelectableLanguages) languages. Remove one to add another."))
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
            fNameError = Self.validateName(fName, hint: String(localized: "Enter First Name"))
            lNameError = Self.validateName(lName, hint: String(localized: "Last Name"))
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
        if value.count < 2 { return String(localized: "Please enter at least 2 characters.") }
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
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
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
