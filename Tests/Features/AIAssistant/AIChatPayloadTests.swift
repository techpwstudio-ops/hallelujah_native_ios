import Foundation
import Testing
@testable import Hallelujah

struct AIChatPayloadTests {
    @Test func textOnlyPayloadStreams() {
        #expect(AISendPayload(message: "Hello").shouldStream)
    }

    @Test func attachmentsAudioOrTtsDisableStreaming() {
        let attachment = AIAttachmentPayload(key: "k", mimeType: "image/jpeg")
        #expect(!AISendPayload(message: "x", attachments: [attachment]).shouldStream)
        #expect(!AISendPayload(message: "x", audioKey: "a").shouldStream)
        #expect(!AISendPayload(message: "x", tts: true).shouldStream)
    }

    @Test func attachmentTypeIsDerivedFromMimeType() {
        #expect(AIAttachmentPayload(key: "k", mimeType: "image/png").type == "image")
        #expect(AIAttachmentPayload(key: "k", mimeType: "audio/mp4").type == "audio")
        #expect(AIAttachmentPayload(key: "k", mimeType: "video/mp4").type == "video")
        #expect(AIAttachmentPayload(key: "k", mimeType: "application/pdf").type == "pdf")
        #expect(AIAttachmentPayload(key: "k", mimeType: "application/octet-stream").type == "image")
    }

    @Test func requestBodyOmitsEmptyFields() throws {
        let body = AISendMessageRequestDTO(payload: AISendPayload(message: "Hi"))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(object["message"] as? String == "Hi")
        #expect(object["attachments"] == nil)
        #expect(object["tts"] == nil)
        #expect(object["audioKey"] == nil)
    }

    @Test func requestBodyCarriesAttachments() throws {
        let payload = AISendPayload(
            message: nil,
            attachments: [AIAttachmentPayload(key: "uploads/a.jpg", mimeType: "image/jpeg")],
            tts: true
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AISendMessageRequestDTO(payload: payload))) as? [String: Any]
        )
        let attachments = try #require(object["attachments"] as? [[String: Any]])
        #expect(attachments.first?["key"] as? String == "uploads/a.jpg")
        #expect(attachments.first?["type"] as? String == "image")
        #expect(attachments.first?["mimeType"] as? String == "image/jpeg")
        #expect(object["tts"] as? Bool == true)
        #expect(object["message"] == nil)
    }

    @MainActor
    @Test func retryPayloadTrimsTextAndKeepsOnlyTypedAttachments() {
        let message = AIMessage(
            id: "1", role: .user, content: "  hello  ", toolData: nil,
            attachments: [AIAttachment(key: "a", mimeType: "image/png"), AIAttachment(key: "b", mimeType: nil)],
            createdAt: Date(), isStreaming: false, isError: true, language: nil
        )
        let payload = AIChatViewModel.payload(for: message)
        #expect(payload?.message == "hello")
        #expect(payload?.attachments.count == 1)
    }

    @MainActor
    @Test func retryPayloadIsNilWhenNothingResendable() {
        let blank = AIMessage.localUser(id: "1", content: "   ")
        #expect(AIChatViewModel.payload(for: blank) == nil)
        let assistant = AIMessage(
            id: "2", role: .assistant, content: "hi", toolData: nil, attachments: [],
            createdAt: Date(), isStreaming: false, isError: true, language: nil
        )
        #expect(AIChatViewModel.payload(for: assistant) == nil)
    }
}
