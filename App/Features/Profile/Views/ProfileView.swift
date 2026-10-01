import SwiftUI

/// Ported from `ProfilePage` (`lib/views/profile/profile_page.dart`) — an
/// edit form for first/last name, date of birth, and gender, plus read-only
/// phone/email rows shown only when the signed-in user actually has them
/// (Dart gates both on `OurSession.instance.user?.mobile`/`.email` being
/// non-null the same way). Reached via the existing `AppRoute.profile` case
/// (no payload). No navigation title is set here — `AppShellView`'s
/// `AppRouteDestinationView` wrapper already supplies one
/// (`.placeholderTitle`, "Profile") for every route it dispatches, the same
/// as `UserPlaylistDetailView`/`CreatorProfileView` don't set their own
/// title either.
///
/// **Deliberate scope cut: no photo upload.** Dart's `UploadPhoto` widget
/// lets the user pick a new photo, crop/compress it
/// (`CropCompressImagePage`), and upload it to S3 (`_pickFromSource`,
/// `FlutterImageCompress`, `S3Service`'s presigned-upload flow).
/// `AccountSetupView`'s own doc comment already named this exact gap as
/// this task's job to close. It still isn't closed here: no S3
/// presigned-upload client exists anywhere in this native app yet (grepped
/// `App/` for any upload/presign networking and found none) — building that
/// pipeline (image picker, crop UI, compression, presigned-upload
/// networking) is substantial, separate infrastructure work, not something
/// a Profile-screen task should invent as a side effect. The avatar below is
/// therefore a read-only display.
struct ProfileView: View {
    var body: some View {
        // `.toastOverlay()` must wrap a *child* view, not decorate this same
        // view's own body — `@Environment(\.toastCenter)` on a view resolves
        // from the environment inherited from its parent, so a modifier this
        // same view applies to its own returned content can never feed back
        // into its own property wrapper (it only reaches that content's
        // subtree). Splitting into a wrapper + inner content view puts the
        // reader genuinely below the injection point, so it sees the real
        // `ToastCenter` instance `.toastOverlay()` renders from, not the
        // unused environment default.
        ProfileContentView()
            .toastOverlay()
    }
}

private struct ProfileContentView: View {
    @State private var viewModel = ProfileViewModel()

    @State private var cachedUser: User?

    @State private var fName = ""
    @State private var lName = ""

    @State private var dateOfBirth: Date?
    @State private var isDatePickerPresented = false
    @State private var pickerDate = Self.maximumBirthDate

    @State private var gender: String?

    // `originalData` — the last-saved (or last-refreshed) snapshot `isChanged`
    // below diffs the live fields against, mirroring Dart's `checkChanges()`.
    @State private var baselineFName = ""
    @State private var baselineLName = ""
    @State private var baselineDateOfBirth: Date?
    @State private var baselineGender: String?

    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.appTheme) private var theme

    /// `DateTime(1900)` / `DateTime.now().subtract(Duration(days: 13 * 365))`
    /// — same bounds as `AccountSetupView`'s identical picker, copied rather
    /// than shared (see this task's own instructions on why).
    private static let minimumBirthDate = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    private static let maximumBirthDate = Calendar.current.date(byAdding: .day, value: -(13 * 365), to: Date()) ?? Date()

    /// `UploadPhoto`'s own default `width`/`height` (`upload_photo_ui.dart`).
    private static let avatarDiameter: CGFloat = 144

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                avatar

                nameField(label: "First Name", placeholder: "First Name", text: $fName, errorMessage: fNameError, contentType: .givenName)
                nameField(label: "Last Name", placeholder: "Last Name", text: $lName, errorMessage: lNameError, contentType: .familyName)

                if let mobile = cachedUser?.mobile, !mobile.isEmpty {
                    AppTextField(text: .constant(mobile), label: "Phone Number", enabled: false)
                }

                if let email = cachedUser?.email, !email.isEmpty {
                    AppTextField(text: .constant(email), label: "Email Address", enabled: false)
                }

                dateField

                genderField

                AppButton(
                    label: "Save",
                    action: { Task { await save() } },
                    isLoading: viewModel.state == .loading,
                    enabled: canSave
                )
                .padding(.top, Spacing.sm)
            }
            .padding(Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.color(.backgroundPrimary))
        // `.toastOverlay()` itself now lives one level up, on `ProfileView`,
        // wrapping this view as a child — see `ProfileView.body`'s comment
        // for why it can't live here instead. No `.toastOverlay()` is
        // installed anywhere above this screen once it's pushed inside
        // `AppShellView`'s signed-in tab stacks (confirmed by grepping every
        // `.toastOverlay()`/`toastCenter` call site in the app — it's only
        // ever self-installed by the pre-sign-in `Authentication`/
        // `AccountSetupView` screens, each for the same "nothing above me
        // provides one" reason). Installing it here too is that same
        // established pattern, not a one-off invention.
        .task {
            await loadCachedUser()
            await reconcileWithRefresh()
        }
        .appSheet(isPresented: $isDatePickerPresented, detents: [.height(340)]) { datePickerContent }
    }

    // MARK: - Avatar

    private var avatar: some View {
        // `.md` — 144pt at up to 3x scale sits between the list-row (`.sm`)
        // and full-hero (`.lg`) variants `ImageVariant`'s own doc comment
        // describes; matches how `HomeRecentItemCardView`'s similarly-sized
        // cards resolve theirs.
        ArtworkView(
            url: ArtworkURLResolver().resolve(path: cachedUser?.image, variant: .md, allowedVariants: cachedUser?.imageVariants),
            width: Self.avatarDiameter,
            height: Self.avatarDiameter,
            cornerRadius: Self.avatarDiameter / 2,
            contentMode: .fill
        )
    }

    // MARK: - Name fields

    private func nameField(
        label: String, placeholder: String, text: Binding<String>, errorMessage: String?, contentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            requiredLabel(label)
            AppTextField(text: text, placeholder: placeholder, textContentType: contentType, errorMessage: errorMessage)
        }
    }

    // MARK: - Date of birth

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 0) {
            requiredLabel("Date Of Birth")

            Spacer().frame(height: Spacing.xs)

            Button {
                pickerDate = dateOfBirth ?? Self.maximumBirthDate
                isDatePickerPresented = true
            } label: {
                HStack {
                    Text(dateOfBirth.map(Self.displayFormatter.string(from:)) ?? "Enter Date Of Birth")
                        .typography(Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundStyle(dateOfBirth == nil ? theme.color(.textTertiary) : theme.color(.textPrimary))
                    Spacer()
                    theme.icon(.calendar)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: Spacing.inputHeight)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(theme.color(.surfaceInput))
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// `_DatePickerSheet` (`custom_inputs.dart`) — same wheel-picker-sheet
    /// pattern as `AccountSetupView.datePickerContent`, copied rather than
    /// shared per this task's own instructions.
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

    // MARK: - Gender

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
                    .foregroundStyle(theme.color(.textPrimary))
                Text(label)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
            }
        }
        .buttonStyle(.plain)
    }

    private func requiredLabel(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
            Text(" * ")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.statusError))
        }
    }

    // MARK: - Validation / change tracking

    private var fNameTrimmed: String { fName.trimmingCharacters(in: .whitespaces) }
    private var lNameTrimmed: String { lName.trimmingCharacters(in: .whitespaces) }

    /// `minLimit: 2` (`textInput`'s validator, `custom_inputs.dart`) — also
    /// covers Dart's separate `required` (non-empty) check, since an empty
    /// trimmed string never satisfies `count >= 2`.
    private var isFNameValid: Bool { fNameTrimmed.count >= 2 }
    private var isLNameValid: Bool { lNameTrimmed.count >= 2 }

    /// Live feedback only for "too short," never for "empty" — with `Save`
    /// disabled until every required field validates (see `canSave` below),
    /// there is no Dart-equivalent submit-tap moment to gate a "required"
    /// message behind, and surfacing it on an untouched, still-empty field
    /// would just be noise.
    private var fNameError: String? {
        guard !fNameTrimmed.isEmpty, !isFNameValid else { return nil }
        return "Please enter at least 2 characters."
    }

    private var lNameError: String? {
        guard !lNameTrimmed.isEmpty, !isLNameValid else { return nil }
        return "Please enter at least 2 characters."
    }

    /// `DateTime.now().difference(date).inDays < (13 * 365)` — same
    /// arithmetic as `AccountSetupView.submit()`'s identical check.
    private var isAgeValid: Bool {
        guard let dateOfBirth else { return false }
        return Date().timeIntervalSince(dateOfBirth) / 86_400 >= Double(13 * 365)
    }

    /// `checkChanges()` — diffs the live fields against `originalData`.
    /// Dart's version loops over every key in the user's full JSON (id,
    /// email, provider, languages, …), but only these four ever actually
    /// change through this form (mobile/email are `edit: false`, and there's
    /// no image picker here — see this file's own doc comment), so diffing
    /// just them has the same real-world effect.
    private var isChanged: Bool {
        fNameTrimmed != baselineFName || lNameTrimmed != baselineLName
            || dateOfBirth != baselineDateOfBirth || gender != baselineGender
    }

    /// Gates `Save`'s `enabled` on change **and** validity — the native
    /// equivalent of Dart's `isChanged`-only gate (a non-interactive grey
    /// container until something changed) tightened so it also never invites
    /// a tap that Dart itself would immediately reject with a toast
    /// ("Please choose gender" / "Please choose date of birth" /
    /// `_form.currentState?.validate()`). `AppButton` has no "enabled but
    /// rejects the tap" mode the way a plain `GestureDetector` does, so
    /// folding validity into the same gate is the closest honest native
    /// equivalent, not a shortcut around it.
    private var canSave: Bool {
        isChanged && isFNameValid && isLNameValid && dateOfBirth != nil && isAgeValid && gender != nil
    }

    // MARK: - Actions

    private func loadCachedUser() async {
        guard let user = await viewModel.loadCachedUser() else { return }
        apply(user)
    }

    /// `initState`'s background refresh
    /// (`OurSession.instance.fetchUserDetails().then((_) { setState(...) })`)
    /// — reconciles the on-screen fields with the freshly-fetched user, but
    /// only while they still match the baseline (`!isChanged`), i.e. the
    /// person hasn't started editing yet. Dart's own refresh has no such
    /// guard, but it also has no real race to guard against on this screen's
    /// actual timing (the request lands well before a person can fill out
    /// three fields by hand); adding the guard natively is the more
    /// defensive form of the same "always show the latest server data"
    /// intent, not a behavior change to it.
    private func reconcileWithRefresh() async {
        guard let user = await viewModel.refreshUser(), !isChanged else { return }
        apply(user)
    }

    /// Always sets both the live fields and the baseline together — every
    /// call site here is a fresh load, never a value to diff against
    /// something already on screen.
    private func apply(_ user: User) {
        cachedUser = user
        fName = user.firstName ?? ""
        lName = user.lastName ?? ""
        gender = user.gender
        dateOfBirth = user.dateOfBirth.flatMap(Self.parseDate)

        baselineFName = fNameTrimmed
        baselineLName = lNameTrimmed
        baselineGender = gender
        baselineDateOfBirth = dateOfBirth
    }

    /// `GestureDetector.onTap`'s handler (`profile_page.dart`) once
    /// `isChanged` is true — validation itself has already happened by the
    /// time this can be called (`canSave` gates the button), so this is just
    /// the save-and-rebaseline half.
    private func save() async {
        guard canSave, viewModel.state != .loading else { return }
        guard let dateOfBirth, let gender else { return }

        let savedFName = fNameTrimmed
        let savedLName = lNameTrimmed

        let success = await viewModel.save(
            fName: savedFName,
            lName: savedLName,
            dateOfBirth: Self.isoFormatter.string(from: dateOfBirth),
            gender: gender
        )

        if success {
            toastCenter.show("Profile updated")
            // `originalData = {...initData}` — the saved values become the
            // new unchanged baseline.
            baselineFName = savedFName
            baselineLName = savedLName
            baselineDateOfBirth = dateOfBirth
            baselineGender = gender
        } else if case let .error(message) = viewModel.state {
            toastCenter.show(message)
        }
    }

    // MARK: - Date formatting

    /// `date.toIso8601String()` on a local, non-UTC `DateTime` — copied
    /// verbatim from `AccountSetupView`'s identical statics (see this file's
    /// own doc comment on why they're copied, not shared).
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

    /// Layered leniency for a `dateOfBirth` that round-tripped through the
    /// server (`updateProfile`'s response) and could come back re-formatted
    /// with a UTC designator rather than in `isoFormatter`'s exact local
    /// shape — same fallback chain as `AccountSetupView.parseDate`.
    private static func parseDate(_ string: String) -> Date? {
        if let date = isoFormatter.date(from: string) { return date }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(\.appTheme, .standard)
}
