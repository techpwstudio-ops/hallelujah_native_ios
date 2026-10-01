import SwiftUI

/// Renders every T13 media component for visual QA — same role as
/// `TokenGalleryView`/`GlassGalleryView`/`ComponentGalleryView` for their
/// own tasks. Preview-only, not part of any real screen.
///
/// The demo image URLs below (`picsum.photos`) are synthetic placeholders,
/// not real CDN paths — there is no `Song`/`Creator` model yet to source
/// real artwork paths from (that lands in a later milestone), the same way
/// `ComponentGalleryView`'s `@State` values are synthetic form input, not
/// ported from any Dart source.
///
/// T13's Done criterion ("artwork view proven not to decode full-size
/// images during scroll") is demonstrated structurally here — a grid reusing
/// a handful of URLs at small render sizes — rather than measured: profiling
/// needs an actual build/run, which is out of scope for this pass (see
/// `progress.md`'s standing constraints). What guarantees the claim is
/// `ArtworkView.load()` passing a downsample target to
/// `ArtworkImageCache`/`ImageIO` before decode, and caching by
/// `url#pixelSize` so identical tiles decode once — both readable directly
/// in `App/Data/Media/ArtworkImageCache.swift`.
struct MediaGalleryView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                artworkSection
                artworkGridSection
                marqueeSection
                seekBarSection
                progressHairlineSection
                likeButtonSection
            }
            .padding(Spacing.md)
        }
        .background(ThemedBackground())
    }

    // MARK: - Artwork (variant sizes)

    private var artworkSection: some View {
        section("Artwork — variant sizes") {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(spacing: Spacing.xs) {
                    ArtworkView(url: Self.demoURL(seed: "sm", size: 56), width: 56, height: 56, cornerRadius: Radius.sm)
                    CaptionLabel("sm")
                }
                VStack(spacing: Spacing.xs) {
                    ArtworkView(url: Self.demoURL(seed: "md", size: 120), width: 120, height: 120, cornerRadius: Radius.md)
                    CaptionLabel("md")
                }
                VStack(spacing: Spacing.xs) {
                    ArtworkView(url: Self.demoURL(seed: "lg", size: 200), width: 200, height: 200, cornerRadius: Radius.lg)
                    CaptionLabel("lg")
                }
                VStack(spacing: Spacing.xs) {
                    ArtworkView(url: nil, width: 96, height: 96, cornerRadius: Radius.md)
                    CaptionLabel("nil url")
                }
            }
        }
    }

    // MARK: - Artwork (scroll / cache reuse)

    private var artworkGridSection: some View {
        section("Artwork — scrolling grid (cache reuse)") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 5), spacing: Spacing.sm) {
                ForEach(0..<20, id: \.self) { index in
                    ArtworkView(
                        url: Self.demoURL(seed: "grid-\(index % 4)", size: 64),
                        width: 64,
                        height: 64,
                        cornerRadius: Radius.sm
                    )
                }
            }
        }
    }

    // MARK: - Marquee

    private var marqueeSection: some View {
        section("Marquee text") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                MarqueeText(text: "Short title")
                    .frame(width: 220)
                MarqueeText(text: "A much longer song title that does not fit in this narrow box and should scroll")
                    .frame(width: 220)
            }
        }
    }

    // MARK: - Seek bar

    private var seekBarSection: some View {
        SeekBarDemo()
    }

    // MARK: - Progress hairline

    private var progressHairlineSection: some View {
        section("Progress hairline") {
            VStack(spacing: Spacing.sm) {
                ProgressHairline(progress: 0.0)
                ProgressHairline(progress: 0.35)
                ProgressHairline(progress: 1.0)
            }
        }
    }

    // MARK: - Like button

    private var likeButtonSection: some View {
        LikeButtonDemo()
    }

    private static func demoURL(seed: String, size: Int) -> URL? {
        URL(string: "https://picsum.photos/seed/\(seed)/\(size)")
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            content()
        }
    }

    private struct CaptionLabel: View {
        let text: String
        @Environment(\.appTheme) private var theme
        init(_ text: String) { self.text = text }
        var body: some View {
            Text(text)
                .typography(Typography.labelSmall)
                .foregroundStyle(theme.color(.textSecondary))
        }
    }

    private struct ThemedBackground: View {
        @Environment(\.appTheme) private var theme
        var body: some View { theme.color(.backgroundPrimary) }
    }
}

/// Standalone so it can hold the `@State` an interactive `SeekBar` demo
/// needs without complicating `MediaGalleryView`'s own body.
private struct SeekBarDemo: View {
    @Environment(\.appTheme) private var theme
    @State private var position: TimeInterval = 45
    @State private var duration: TimeInterval = 210
    @State private var buffered: TimeInterval = 90

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Seek bar")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            SeekBar(position: position, duration: duration, buffered: buffered) { newPosition in
                position = newPosition
            }
        }
    }
}

private struct LikeButtonDemo: View {
    @Environment(\.appTheme) private var theme
    @State private var likedOff = false
    @State private var likedOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Like button")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
            HStack(spacing: Spacing.md) {
                LikeButton(isLiked: likedOff) { likedOff.toggle() }
                LikeButton(isLiked: likedOn) { likedOn.toggle() }
                LikeButton(isLiked: false, isLoading: true) {}
            }
        }
    }
}

#Preview("Light") {
    MediaGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MediaGalleryView()
        .environment(\.appTheme, .standard)
        .preferredColorScheme(.dark)
}
