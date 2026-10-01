import SwiftUI

/// Completes the pre-existing, already-declared `AppRoute` case
/// `.bibleVerseShare(verseReference:verseText:deepLinkURL:)`
/// (`AppRoute.swift` — never constructed until now). `AppShellView`'s
/// `AppRouteDestinationView` pushes every route's content inside a
/// `NavigationStack` it already owns and applies `.navigationTitle`/
/// `.navigationBarTitleDisplayMode(.inline)` itself (see e.g. `DownloadsView`,
/// `GenreSongsView` in that same switch) — so this view, like those, has no
/// `NavigationStack` or `navigationTitle` of its own; wiring the new switch
/// case there is a deferred `AppShellView` patch outside this task's scope
/// (that file is on the forbidden-to-edit list).
///
/// No existing `ShareLink`/custom share-sheet convention was found anywhere
/// under `App/` (grepped for `ShareLink(` — no matches), so this defaults to
/// the plain native `ShareLink`, the standard SwiftUI share affordance,
/// rather than inventing a bespoke wrapper.
struct BibleVerseShareView: View {
    let verseReference: String
    let verseText: String
    let deepLinkURL: String

    @Environment(\.appTheme) private var theme

    private var shareURL: URL? { URL(string: deepLinkURL) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verseReference)
                        .typography(Typography.headlineMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                    Text(verseText)
                        .typography(Typography.bodyLarge)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(theme.color(.surfacePrimary))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Link")
                        .typography(Typography.labelLarge)
                        .foregroundStyle(theme.color(.textTertiary))
                    Text(deepLinkURL)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .textSelection(.enabled)
                }

                if let shareURL {
                    ShareLink(item: shareURL) {
                        HStack(spacing: Spacing.sm) {
                            theme.icon(.share)
                            Text("Share Verse")
                                .typography(Typography.titleSmall)
                        }
                        .foregroundStyle(theme.color(.textInverse))
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.buttonHeight)
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(theme.color(.textPrimary))
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(theme.color(.backgroundPrimary).ignoresSafeArea())
    }
}
