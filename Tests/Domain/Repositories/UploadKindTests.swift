import Testing
@testable import GHallelujah

/// `AiService._uploadTypeFromExt` + the profile photo's fixed type.
struct UploadKindTests {
    @Test func wireValues() {
        #expect(UploadKind.profilePhoto.wireValue == "thumbnail-profile")
        #expect(UploadKind.aiImage.wireValue == "ai-image")
        #expect(UploadKind.aiAudio.wireValue == "ai-audio")
        #expect(UploadKind.aiVideo.wireValue == "ai-video")
    }

    @Test func extensionsMapToTheAIUploadType() {
        for ext in ["jpg", "JPEG", "png", "gif", "webp"] {
            #expect(UploadKind.aiKind(forExtension: ext) == .aiImage)
        }
        for ext in ["mp3", "m4a", "wav", "ogg"] {
            #expect(UploadKind.aiKind(forExtension: ext) == .aiAudio)
        }
        #expect(UploadKind.aiKind(forExtension: "mp4") == .aiVideo)
        #expect(UploadKind.aiKind(forExtension: "exe") == nil)
    }
}
