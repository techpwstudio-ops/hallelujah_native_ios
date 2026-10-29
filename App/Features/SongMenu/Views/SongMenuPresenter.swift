import SwiftUI

extension View {
    /// Presents the song menu for `song` (set it to show the menu, it resets
    /// to `nil` on dismissal) and carries out whatever the chosen action asks
    /// of the app — toasts, the plans screen, the artist page, the queue, the
    /// sleep-timer sheet. `leavesPlayer` is true when the host is the full
    /// player, which must close itself before navigating elsewhere (Dart's
    /// `NavigationService.popPlayerScreens`).
    func songMenu(song: Binding<Song?>, userPlaylistID: String? = nil, leavesPlayer: Bool = false) -> some View {
        modifier(SongMenuPresenter(song: song, userPlaylistID: userPlaylistID, leavesPlayer: leavesPlayer))
    }

    /// The sleep-timer duration sheet, shared by the player button and the
    /// song menu's "Sleep timer" row.
    func sleepTimerSheet(isPresented: Binding<Bool>) -> some View {
        modifier(SleepTimerSheetPresenter(isPresented: isPresented))
    }
}

private struct SleepTimerSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @State private var sleepTimer: SleepTimerController = DependencyContainer.current.resolve()

    /// Tall enough for the header, six option rows and the "Turn Off Timer"
    /// row shown while a timer runs (~530pt); the default `.medium` clipped
    /// the header in that state. `.large` stays for larger Dynamic Type.
    private static let detents: Set<PresentationDetent> = [.height(580), .large]

    func body(content: Content) -> some View {
        content.appSheet(isPresented: $isPresented, detents: Self.detents) {
            SleepTimerSheet(controller: sleepTimer) { isPresented = false }
        }
    }
}

private struct SongMenuPresenter: ViewModifier {
    @Binding var song: Song?
    let userPlaylistID: String?
    let leavesPlayer: Bool

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter
    @State private var isSleepTimerSheetPresented = false

    /// Lets one sheet finish dismissing before the next presents; SwiftUI
    /// drops a sheet presented while another is mid-dismissal.
    private static let sheetHandoffDelay: Duration = .milliseconds(400)

    private var isPresented: Binding<Bool> {
        Binding(get: { song != nil }, set: { if !$0 { song = nil } })
    }

    func body(content: Content) -> some View {
        content
            .appSheet(isPresented: isPresented, detents: [.fraction(0.8), .fraction(0.95)]) {
                if let song {
                    SongMenuSheet(song: song, userPlaylistID: userPlaylistID) { handle($0) }
                }
            }
            .sleepTimerSheet(isPresented: $isSleepTimerSheetPresented)
    }

    private func handle(_ outcome: SongMenuOutcome) {
        switch outcome {
        case .notice(let text):
            toastCenter.show(text)
            return
        case .message(let text):
            toastCenter.show(text)
        case .dismiss:
            break
        case .openQueue:
            if leavesPlayer { coordinator.pushInPlayer(.queue) } else { coordinator.presentPlayer() }
        case .openSleepTimer:
            Task {
                try? await Task.sleep(for: Self.sheetHandoffDelay)
                isSleepTimerSheetPresented = true
            }
        case .requiresPremium:
            leavePlayerIfNeeded()
            coordinator.push(.subscriptionPlans)
        case .stopped:
            leavePlayerIfNeeded()
        case .reported:
            toastCenter.show("Report sent")
            leavePlayerIfNeeded()
        case .goToArtist(let creatorID):
            leavePlayerIfNeeded()
            coordinator.push(.creatorSongs(creatorID: creatorID, userPlaylistID: nil))
        case .createPlaylist(let songID):
            leavePlayerIfNeeded()
            coordinator.push(.createPlaylist(userPlaylistID: nil, songType: nil, songID: songID))
        }
        song = nil
    }

    private func leavePlayerIfNeeded() {
        if leavesPlayer { coordinator.dismissFullScreen() }
    }
}

/// The trailing "more" control on a song row; opens the row's own song menu.
struct SongMenuButton: View {
    let song: Song
    var userPlaylistID: String?

    @State private var menuSong: Song?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button { menuSong = song } label: {
            theme.icon(.more)
                .foregroundStyle(theme.color(.textTertiary))
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .songMenu(song: $menuSong, userPlaylistID: userPlaylistID)
    }
}
