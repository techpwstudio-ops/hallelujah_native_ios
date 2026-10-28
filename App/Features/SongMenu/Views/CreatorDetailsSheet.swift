import SwiftUI
import Observation

/// Follow state for `CreatorDetailsSheet`. Dart watches `songByIdProvider` so
/// the button tracks every toggle; here the sheet owns the optimistic flag and
/// reverts when the request fails.
@MainActor
@Observable
final class CreatorDetailsViewModel {
    let creator: Creator
    private let fetchedFollowersCount: Int

    private let repository: any CreatorRepository

    init(creator: Creator, container: DependencyContainer = .current) {
        self.creator = creator
        fetchedFollowersCount = creator.followersCount ?? 0
        repository = container.resolve()
    }

    /// Shared with every other follow button (`CreatorFollowStore`).
    var isFollowing: Bool {
        CreatorFollowStore.shared.isFollowing(creator.creatorId, fallback: creator.isFollowing)
    }

    /// The fetched count, moved by one when the follow state changed since.
    var followersCount: Int {
        if isFollowing == (creator.isFollowing == true) { return fetchedFollowersCount }
        return isFollowing ? fetchedFollowersCount + 1 : max(fetchedFollowersCount - 1, 0)
    }

    /// Returns false when the toggle failed and was reverted.
    func toggleFollow() async -> Bool {
        guard let id = creator.creatorId else { return false }
        let store = CreatorFollowStore.shared
        let target = !isFollowing
        let previousState = store.state(for: id)
        store.set(target, for: id)
        do {
            if target { try await repository.follow(creatorId: id) } else { try await repository.unfollow(creatorId: id) }
            return true
        } catch {
            store.set(previousState, for: id)
            return false
        }
    }

    nonisolated static func listenersText(_ count: Int) -> String? {
        count > 0 ? String(localized: "\(count) Listeners") : nil
    }
}

/// `CreatorDetailsSheet` (`lib/sheets/song/creator_details_sheet.dart`),
/// opened from the player's creator card: 357pt rounded (10) artwork, a row
/// with "<n> Listeners" (white 72%), share icon and a 123pt pill
/// Follow / Following button, the name (headlineSmall w600) and the bio
/// (white 72%, w300, 1.5 line height). Padding 16/10/16/32.
struct CreatorDetailsSheet: View {
    @State private var viewModel: CreatorDetailsViewModel
    @State private var showsShare = false
    var onFollowingChange: () -> Void = {}

    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    init(creator: Creator, onFollowingChange: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: CreatorDetailsViewModel(creator: creator))
        self.onFollowingChange = onFollowingChange
    }

    var body: some View {
        if showsShare, let id = viewModel.creator.creatorId {
            ShareSheetView(
                target: .creator(id: id),
                title: viewModel.creator.name ?? "",
                subtitle: nil,
                artworkURL: artworkURL(.lg)
            )
        } else {
            details
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Dart's `screenWidth - 32` is the full width inside the 16pt
                // padding; measured here, so on iPad/Mac it follows the
                // sheet rather than the screen.
                GeometryReader { proxy in
                    ArtworkView(url: artworkURL(.lg), width: proxy.size.width, height: 357, cornerRadius: 10)
                }
                .frame(height: 357)
                Spacer().frame(height: 16)
                HStack(spacing: 10) {
                    if let text = CreatorDetailsViewModel.listenersText(viewModel.followersCount) {
                        Text(text)
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    Button { showsShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                    followButton
                }
                Spacer().frame(height: 8)
                Text(viewModel.creator.name ?? "")
                    .typography(TypographyToken(size: 24, weight: .semibold, lineHeightMultiple: 1.33))
                    .foregroundStyle(Color.white)
                Spacer().frame(height: 8)
                if let bio = viewModel.creator.bio, !bio.isEmpty {
                    Text(bio)
                        .typography(TypographyToken(size: 14, weight: .light, lineHeightMultiple: 1.5))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer().frame(height: 24)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 32, trailing: 16))
        }
    }

    private var followButton: some View {
        Button {
            onFollowingChange()
            Task {
                if await !viewModel.toggleFollow() { toastCenter.show("Network error") }
            }
        } label: {
            Text(viewModel.isFollowing ? "Following" : "Follow")
                .typography(TypographyToken(size: 12, weight: .medium, lineHeightMultiple: 1.33))
                .foregroundStyle(Color.white)
                .frame(width: 123)
                .padding(.vertical, 10)
                .background(
                    viewModel.isFollowing ? Color.white.opacity(0.12) : Color(red: 0.173, green: 0.173, blue: 0.173),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFollowing)
    }

    private func artworkURL(_ variant: ImageVariant) -> URL? {
        ArtworkURLResolver().resolve(path: viewModel.creator.image, variant: variant, allowedVariants: viewModel.creator.imageVariants, fallbackName: viewModel.creator.name)
    }
}
