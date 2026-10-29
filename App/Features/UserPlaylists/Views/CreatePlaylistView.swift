import SwiftUI

/// Ports `CreatePlaylistPage` (`lib/views/library/create_playlist.dart`): a
/// yellow-to-black gradient backdrop (`gradiantDecorationCreate`), a close
/// button, a 120pt translucent circle with a music-list glyph, the heading
/// ("Name your playlist" / "Rename playlist", `headlineSmall` w600, centred),
/// a centred underline text field (60-character limit with a counter,
/// "My playlist" hint), a full-width white 14pt-radius "Create playlist" /
/// "Save changes" button, and a muted "Cancel". Submitting an empty name
/// toasts "Please enter a playlist name and try again!"; while submitting the
/// whole screen is a centred spinner.
struct CreatePlaylistView: View {
    @State private var viewModel: CreatePlaylistViewModel
    @State private var title = ""
    @FocusState private var isFocused: Bool

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    private static let maxLength = 60
    private static let headingStyle = TypographyToken(size: 24, weight: .semibold, lineHeightMultiple: 1.33)
    private static let fieldStyle = TypographyToken(size: 20, weight: .medium, lineHeightMultiple: 1.4)
    private static let buttonStyle = TypographyToken(size: 16, weight: .semibold, lineHeightMultiple: 1.0)
    private static let cancelStyle = TypographyToken(size: 15, weight: .regular, lineHeightMultiple: 1.0)

    init(userPlaylistID: String?, songID: String?) {
        _viewModel = State(initialValue: CreatePlaylistViewModel(userPlaylistID: userPlaylistID, songID: songID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.isSubmitting || viewModel.isLoadingExisting {
                ParitySpinner(fills: true)
                    .frame(maxHeight: .infinity)
            } else {
                LinearGradient(
                    colors: [
                        ParityColor.yellow500.opacity(0.3),
                        ParityColor.grey.opacity(0.1),
                        Color.black.opacity(0.5),
                        Color.black.opacity(0.9),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                content
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard let existingTitle = await viewModel.loadExistingTitle() else { return }
            title = existingTitle
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                ParityIconButton(systemName: "xmark", size: 22, tooltip: "Close") { coordinator.pop() }
                Spacer()
            }

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 20)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))

                    Spacer().frame(height: 28)

                    Text(viewModel.isEditing ? "Rename playlist" : "Name your playlist")
                        .typography(Self.headingStyle)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 40)

                    field

                    Spacer().frame(height: 48)

                    Button { Task { await submit() } } label: {
                        Text(viewModel.isEditing ? "Save changes" : "Create playlist")
                            .typography(Self.buttonStyle)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer().frame(height: 12)

                    Button { coordinator.pop() } label: {
                        Text("Cancel")
                            .typography(Self.cancelStyle)
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(ParityColor.greySubtle)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 32)
                // Native-only tablet/Mac adaptation: a centred form column
                // instead of a field and button the width of the window.
                .readableContentWidth(AdaptiveLayout.formWidth)
            }
            .scrollDismissesKeyboard(.interactively)

            // `Ios26BottomSpacing(multiply: 2)` (hidden while the keyboard is up).
            if !isFocused {
                Color.clear.frame(height: 16)
            }
        }
    }

    /// `TextField(textAlign: center, maxLength: 60)` with white30 underline
    /// (white 1.5pt when focused), 12pt vertical padding and a right-aligned
    /// white35 counter.
    private var field: some View {
        VStack(spacing: 0) {
            TextField(
                "",
                text: Binding(
                    get: { title },
                    set: { title = String($0.prefix(Self.maxLength)) }
                ),
                prompt: Text("My playlist").foregroundColor(Color.white.opacity(0.28))
            )
            .typography(Self.fieldStyle)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { Task { await submit() } }
            .padding(.vertical, 12)

            Rectangle()
                .fill(isFocused ? Color.white : Color.white.opacity(0.3))
                .frame(height: isFocused ? 1.5 : 1)

            HStack {
                Spacer()
                Text("\(title.count)/\(Self.maxLength)")
                    .font(.custom(Typography.fontFamily, size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.top, 8)
        }
    }

    /// `_submit` — pop THEN push, in that order, on either a create or a
    /// rename success; a failure leaves this screen up with
    /// `viewModel.errorMessage` now set.
    private func submit() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toastCenter.show("Please enter a playlist name and try again!")
            return
        }
        isFocused = false
        guard let result = await viewModel.submit(title: title) else { return }
        coordinator.pop()
        coordinator.push(.userPlaylistSongs(playlistID: result.id))
    }
}
