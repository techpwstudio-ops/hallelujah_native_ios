import Testing
@testable import GHallelujah

struct ArtworkURLResolverTests {
    private let resolver = ArtworkURLResolver(configuration: .staging)

    @Test func missingOrEmptyPathResolvesToNil() {
        #expect(resolver.resolve(path: nil, variant: .sm, allowedVariants: nil) == nil)
        #expect(resolver.resolve(path: "", variant: .sm, allowedVariants: nil) == nil)
    }

    @Test func absoluteHTTPSURLsPassThroughUntouched() {
        let url = resolver.resolve(path: "https://example.com/a.png", variant: .md, allowedVariants: nil)
        #expect(url?.absoluteString == "https://example.com/a.png")
    }

    @Test func bareStoragePathsGoThroughTheProxy() {
        let url = resolver.resolve(path: "songs/1/cover.png", variant: .md, allowedVariants: nil)
        #expect(url?.host == AppConfiguration.staging.proxyBaseURL.host)
        #expect(url?.path.hasSuffix("/proxy") == true)
        #expect(url?.query == "path=songs/1/cover.png")
    }

    @Test func thumbnailPathsUseTheRequestedVariantWhenAllowed() {
        let url = resolver.resolve(path: "x/thumbnails/original.webp", variant: .sm, allowedVariants: "sm,md")
        #expect(url?.lastPathComponent == "sm.webp")
    }

    @Test func thumbnailPathsKeepTheOriginalWhenTheVariantIsNotAllowed() {
        let url = resolver.resolve(path: "x/thumbnails/original.webp", variant: .lg, allowedVariants: "sm,md")
        #expect(url?.lastPathComponent == "original.webp")
    }

    @Test func systemAvatarsNeverRewriteToAVariant() {
        let path = "hallelujah/system/public/avatars/thumbnails/a.webp"
        let url = resolver.resolve(path: path, variant: .sm, allowedVariants: "sm")
        #expect(url?.lastPathComponent == "a.webp")
    }
}
