import PhotosUI
import SwiftUI

/// Ports `ProfilePage` (`lib/views/profile/profile_page.dart`) 1:1: black
/// scaffold, 8pt screen padding, `UploadPhoto` (144pt circle + 40pt edit
/// button, "Select Image Source" sheet, crop page), Flutter-styled fields,
/// radio gender row and a white "Save" bar that is inert until something
/// changed. Validation runs on Save-tap like the Dart `Form`; a successful
/// save pops back with "Profile updated successfully".
///
/// A newly cropped photo is uploaded through `UploadRepository` (presigned
/// S3 PUT) on Save and its key sent as `image`, like `AuthBloc._updateProfile`.
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
    @State private var showValidation = false

    // Photo
    @State private var imageLocalURL: URL?
    @State private var isSourceSheetPresented = false
    @State private var pendingSource: PhotoSource?
    @State private var isPhotosPickerPresented = false
    @State private var photosSelection: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var cropSourceURL: URL?

    private enum PhotoSource { case camera, gallery }

    // `originalData` snapshot `isChanged` diffs against (`checkChanges()`).
    @State private var baselineFName = ""
    @State private var baselineLName = ""
    @State private var baselineDateOfBirth: Date?
    @State private var baselineGender: String?

    @Environment(\.toastCenter) private var toastCenter
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let minimumBirthDate = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    private static let maximumBirthDate = Calendar.current.date(byAdding: .day, value: -(13 * 365), to: Date()) ?? Date()

    /// `UploadPhoto` default width/height.
    private static let avatarDiameter: CGFloat = 144

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    avatarSection

                    textField(label: "First Name", text: $fName, error: fNameError, contentType: .givenName)
                    textField(label: "Last Name", text: $lName, error: lNameError, contentType: .familyName)

                    if let mobile = cachedUser?.mobile {
                        readOnlyField(label: "Phone Number", value: mobile, keyboard: .phonePad)
                    }
                    if let email = cachedUser?.email {
                        readOnlyField(label: "Email Address", value: email, keyboard: .emailAddress)
                    }

                    dateField
                    genderField
                }
            }
            .scrollDismissesKeyboard(.interactively)

            saveBar
        }
        .padding(Dimens.screenPaddingAll)
        .parityScaffold()
        .parityNavTitle("Profile")
        .task {
            await loadCachedUser()
            await reconcileWithRefresh()
        }
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerContent
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(AccountParity.sheetBackground)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $isSourceSheetPresented, onDismiss: handleSourceDismissed) {
            sourceSheet
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(AccountParity.sheetBackground)
                .presentationCornerRadius(16)
        }
        .photosPicker(isPresented: $isPhotosPickerPresented, selection: $photosSelection, matching: .images)
        .onChange(of: photosSelection) { _, item in
            guard let item else { return }
            Task {
                let url = await ProfileImageSupport.writeTempFile(from: item)
                photosSelection = nil
                if let url {
                    cropSourceURL = url
                } else {
                    toastCenter.show("Failed to pick image")
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { url in
                isCameraPresented = false
                if let url {
                    // Let the camera cover finish dismissing before the crop cover presents.
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        cropSourceURL = url
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(get: { cropSourceURL != nil }, set: { if !$0 { cropSourceURL = nil } })) {
            if let source = cropSourceURL {
                CropImageView(sourceURL: source) { cropped in
                    cropSourceURL = nil
                    guard let cropped else { return }
                    if let compressed = ProfileImageSupport.compress(cropped) {
                        imageLocalURL = compressed
                    } else {
                        toastCenter.show("Image compression failed")
                    }
                }
            }
        }
    }

    // MARK: - Avatar (`UploadPhoto`)

    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Color.white)
                if let imageLocalURL, let image = UIImage(contentsOfFile: imageLocalURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
                        .clipShape(Circle())
                } else if let path = cachedUser?.image, !path.isEmpty {
                    ArtworkView(
                        url: ArtworkURLResolver().resolve(path: path, variant: .md, allowedVariants: cachedUser?.imageVariants),
                        width: Self.avatarDiameter,
                        height: Self.avatarDiameter,
                        cornerRadius: Self.avatarDiameter / 2,
                        contentMode: .fill
                    )
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(AccountParity.grey)
                }
            }
            .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
            .padding(8)

            Button {
                isSourceSheetPresented = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .glassCircle(interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Edit photo")
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private var sourceSheet: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            HStack {
                Text("Select Image Source")
                    .font(AccountParity.titleMedium)
                    .foregroundStyle(AccountParity.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            Spacer().frame(height: 12)
            sourceTile(icon: "camera", title: "Take Photo") { pick(.camera) }
            sourceTile(icon: "photo.on.rectangle", title: "Choose from Gallery") { pick(.gallery) }
            Spacer().frame(height: 8)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
    }

    private func sourceTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(AccountParity.white)
                    .frame(width: 24)
                Text(title)
                    .font(AccountParity.bodyLarge)
                    .foregroundStyle(AccountParity.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ source: PhotoSource) {
        pendingSource = source
        isSourceSheetPresented = false
    }

    private func handleSourceDismissed() {
        guard let source = pendingSource else { return }
        pendingSource = nil
        switch source {
        case .gallery:
            isPhotosPickerPresented = true
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                isCameraPresented = true
            } else {
                toastCenter.show("Failed to pick image")
            }
        }
    }

    // MARK: - Fields

    private func textField(label: String, text: Binding<String>, error: String?, contentType: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ParityRequiredLabel(text: label)
                .padding(.bottom, 8)
            ParityTextField(
                text: text,
                placeholder: label,
                errorMessage: error,
                keyboard: .default,
                contentType: contentType
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func readOnlyField(label: String, value: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ParityRequiredLabel(text: label)
                .padding(.bottom, 8)
            ParityTextField(text: .constant(value), placeholder: label, enabled: false, keyboard: keyboard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Date of birth (`dateInput`)

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Date Of Birth").font(AccountParity.titleSmall).foregroundStyle(AccountParity.white)
                + Text(" * ").font(AccountParity.bodyMedium).foregroundStyle(Color.red))
                .padding(.bottom, 8)

            Button {
                pickerDate = dateOfBirth ?? Self.maximumBirthDate
                isDatePickerPresented = true
            } label: {
                HStack {
                    Text(dateOfBirth.map(Self.displayFormatter.string(from:)) ?? "Enter Date Of Birth")
                        .font(AccountParity.font(14, .medium))
                        .foregroundStyle(dateOfBirth == nil ? Color(red: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255) : AccountParity.white)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(AccountParity.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(AccountParity.fill)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// `_DatePickerSheet`: drag handle, close / check icon row, 220pt picker.
    private var datePickerContent: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            HStack {
                Button {
                    isDatePickerPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AccountParity.white60)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Button {
                    dateOfBirth = pickerDate
                    isDatePickerPresented = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AccountParity.white)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Select")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            DatePicker(
                "Date of Birth",
                selection: $pickerDate,
                in: Self.minimumBirthDate...Self.maximumBirthDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.colorScheme, .dark)
            .frame(height: 220)
            Spacer().frame(height: 8)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Gender

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gender *")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .padding(.horizontal, 4)
            HStack(spacing: 0) {
                genderOption(label: "Male", value: "male")
                genderOption(label: "Female", value: "female")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private func genderOption(label: String, value: String) -> some View {
        Button {
            gender = value
        } label: {
            HStack(spacing: 0) {
                Image(systemName: gender == value ? "circle.inset.filled" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(gender == value ? AccountParity.grey : Color(red: 0.79, green: 0.77, blue: 0.82))
                    .frame(width: 48, height: 48)
                Text(label)
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white)
                    .padding(.trailing, 8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save bar (`MyContainer` + `GestureDetector`)

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            Text("Save")
                .font(AccountParity.titleSmall)
                .foregroundStyle(isChanged ? Color.black : AccountParity.grey)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(isChanged ? Color.white : Color(white: 0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .strokeBorder(isChanged ? Color.white : Color(white: 0.74), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isChanged || viewModel.state == .loading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Validation / change tracking

    private var fNameTrimmed: String { fName.trimmingCharacters(in: .whitespaces) }
    private var lNameTrimmed: String { lName.trimmingCharacters(in: .whitespaces) }

    /// `minLimit: 2` (`textInput`'s validator, `custom_inputs.dart`) — also
    /// covers Dart's separate `required` (non-empty) check, since an empty
    /// trimmed string never satisfies `count >= 2`.
    private var isFNameValid: Bool { fNameTrimmed.count >= 2 }
    private var isLNameValid: Bool { lNameTrimmed.count >= 2 }

    /// Dart's `Form.validate()` runs on Save-tap: empty -> the field hint,
    /// too short -> "Please enter at least 2 characters.".
    private var fNameError: String? {
        guard showValidation else { return nil }
        if fNameTrimmed.isEmpty { return "First Name" }
        return isFNameValid ? nil : "Please enter at least 2 characters."
    }

    private var lNameError: String? {
        guard showValidation else { return nil }
        if lNameTrimmed.isEmpty { return "Last Name" }
        return isLNameValid ? nil : "Please enter at least 2 characters."
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
            || imageLocalURL != nil
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

    /// Save-tap handler (`profile_page.dart`): validate, toast on the first
    /// failing rule, save, then pop with "Profile updated successfully".
    private func save() async {
        guard isChanged, viewModel.state != .loading else { return }
        showValidation = true
        guard isFNameValid, isLNameValid else { return }
        guard let gender else {
            toastCenter.show("Please choose gender")
            return
        }
        guard let dateOfBirth else {
            toastCenter.show("Please choose date of birth")
            return
        }
        guard isAgeValid else {
            toastCenter.show("Please choose valid date of birth, minimum 13 year old")
            return
        }

        let success = await viewModel.save(
            fName: fNameTrimmed,
            lName: lNameTrimmed,
            dateOfBirth: Self.isoFormatter.string(from: dateOfBirth),
            gender: gender,
            imageFileURL: imageLocalURL
        )

        if success {
            toastCenter.show("Profile updated successfully")
            coordinator.pop()
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
    .environment(AppNavigationCoordinator())
}
