import Foundation

/// T58 — native SwiftUI port of the Flutter app's AI chat feature. Domain
/// shapes only; DTOs and their wire mapping live in `App/Data/DTOs/
/// AIChatDTOs.swift`. Grounded directly against the task's own backend HTTP
/// contract (already fully researched before this file was written, not
/// re-derived here) rather than a specific controller source file.

// MARK: - Role

enum AIRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
}

// MARK: - Attachments

/// One already-uploaded attachment on a persisted message — `{key, mimeType}`
/// per the message JSON shape in T58's backend contract.
struct AIAttachment: Codable, Sendable, Equatable {
    let key: String
    let mimeType: String?
}

// MARK: - Tool results

/// `JSONValue` (`Core/Networking/Models/JSONValue.swift`) has no `Equatable`
/// conformance of its own; `AIToolResult` below needs one (it's declared
/// `Equatable` per spec) so this adds it retroactively here rather than
/// editing that file, which is out of this task's scope. Auto-synthesis only
/// fires for a conformance declared in the same file as the type itself, so
/// this is written by hand, case by case, recursing the same way the type
/// itself does.
extension JSONValue: Equatable {
    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let left), .string(let right)): left == right
        case (.number(let left), .number(let right)): left == right
        case (.bool(let left), .bool(let right)): left == right
        case (.object(let left), .object(let right)): left == right
        case (.array(let left), .array(let right)): left == right
        case (.null, .null): true
        default: false
        }
    }
}

/// One `{name, result}` entry from the tool-data embedding protocol — see
/// `AIMessage.parseRawContent(raw:)` below for the full contract.
struct AIToolResult: Codable, Sendable, Equatable {
    let name: String
    let result: JSONValue
}

// MARK: - Message

/// One chat turn, user or assistant. A plain mutable struct — no `copyWith`
/// helper; a caller holding one in an array (`messages[index].isStreaming =
/// false`) mutates the `var` fields directly through subscript access.
struct AIMessage: Identifiable, Sendable, Equatable {
    let id: String
    let role: AIRole
    var content: String?
    var toolData: [AIToolResult]?
    let attachments: [AIAttachment]
    let createdAt: Date
    var isStreaming: Bool
    var isError: Bool
    var language: String?
}

extension AIMessage {
    /// An optimistic local row inserted into the transcript the instant the
    /// user hits send, before the server round-trip returns its own
    /// persisted `userMessage`.
    static func localUser(id: String, content: String?, attachments: [AIAttachment] = []) -> AIMessage {
        AIMessage(
            id: id,
            role: .user,
            content: content,
            toolData: nil,
            attachments: attachments,
            createdAt: Date(),
            isStreaming: false,
            isError: false,
            language: nil
        )
    }

    /// The fixed id `streamingPlaceholder()` defaults to — stable enough for
    /// a caller to detect "this row is the live-streaming assistant turn"
    /// by id alone, independent of `isStreamingPlaceholder` below.
    static let streamingPlaceholderID = "streaming_placeholder"

    /// The not-yet-started assistant row shown the instant a send kicks off
    /// streaming, before the first `.delta` arrives.
    static func streamingPlaceholder(id: String = AIMessage.streamingPlaceholderID) -> AIMessage {
        AIMessage(
            id: id,
            role: .assistant,
            content: nil,
            toolData: nil,
            attachments: [],
            createdAt: Date(),
            isStreaming: true,
            isError: false,
            language: nil
        )
    }

    /// `isStreaming && content == nil`, not `id == Self.streamingPlaceholderID`:
    /// the id-based check would keep reporting `true` after the first delta
    /// mutates `content` in place (unless a caller also swapped the id out),
    /// while this tracks the live "still empty, nothing to show yet" state
    /// directly and turns `false` on its own the moment real text lands.
    var isStreamingPlaceholder: Bool {
        isStreaming && content == nil
    }
}

extension AIMessage {
    /// The tool-data embedding protocol: the server can prefix a message's
    /// raw wire `content` with the literal marker below, followed by a JSON
    /// array of `{name, result}` entries running up to the first newline,
    /// followed by the real display text (if any). One shared, pure
    /// implementation so every code path that sees raw content — DTO decode
    /// (`AIMessageDTO.toDomain()`) and any future live-streaming buffer that
    /// re-parses the growing delta text the same way — applies identical
    /// rules rather than each reimplementing this.
    static let toolDataMarker = "__TD__"

    /// Pure — no I/O. Returns `content: nil` (not `""`) when nothing is left
    /// to show after the prefix is stripped, and dedupes `toolData` entries
    /// by the pair `(name, JSON-encoded result)` so a tool call the server
    /// repeats verbatim mid-stream doesn't produce two cards.
    static func parseRawContent(raw: String?) -> (content: String?, toolData: [AIToolResult]?) {
        guard let raw, raw.hasPrefix(toolDataMarker) else {
            return (raw, nil)
        }

        let afterMarker = raw.dropFirst(toolDataMarker.count)
        let jsonText: Substring
        let remainder: String
        if let newlineIndex = afterMarker.firstIndex(of: "\n") {
            jsonText = afterMarker[afterMarker.startIndex..<newlineIndex]
            remainder = String(afterMarker[afterMarker.index(after: newlineIndex)...])
        } else {
            // No newline at all — the whole string is just the tool-data
            // header, nothing left to display.
            jsonText = afterMarker
            remainder = ""
        }

        return (remainder.isEmpty ? nil : remainder, dedupedToolData(from: String(jsonText)))
    }

    private static func dedupedToolData(from jsonText: String) -> [AIToolResult]? {
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AIToolResult].self, from: data),
              !decoded.isEmpty else {
            return nil
        }

        let encoder = JSONEncoder()
        var seenKeys = Set<String>()
        var deduped: [AIToolResult] = []
        for entry in decoded {
            let resultJSON = (try? encoder.encode(entry.result)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // NUL can't appear in either component, so it's a safe separator
            // for a composite dedupe key.
            let key = "\(entry.name)\u{0}\(resultJSON)"
            if seenKeys.insert(key).inserted {
                deduped.append(entry)
            }
        }
        return deduped.isEmpty ? nil : deduped
    }
}

// MARK: - Send payload

/// A future attachment-send entry's shape. v1 callers always pass an empty
/// `[AIAttachmentPayload]()` — attachment/image upload UI is out of T58 v1
/// scope — this type exists only so a later attachment feature doesn't need
/// to reshape `AISendPayload` itself.
struct AIAttachmentPayload: Sendable {
    let key: String
    let mimeType: String
}

struct AISendPayload: Sendable {
    let message: String?
    let attachments: [AIAttachmentPayload]

    /// v1 has no audio/TTS send path, so streaming (`AIChatStreamingClient`)
    /// is the only send mode whenever there are no attachments to upload
    /// first; the moment `attachments` is non-empty, sending falls back to
    /// the non-streaming `AIChatRepository.sendMessage` path instead.
    var shouldStream: Bool {
        attachments.isEmpty
    }
}

// MARK: - Conversation / suggestion

struct AIConversation: Identifiable, Sendable, Equatable {
    let id: String
    let title: String?
    let lastMessageSnippet: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AISuggestion: Identifiable, Sendable, Equatable {
    let id: String
    let text: String
    let category: String?
}
