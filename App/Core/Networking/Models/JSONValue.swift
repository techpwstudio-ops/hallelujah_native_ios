import Foundation

/// A structural mirror of one JSON value — String/Number/Bool/Object/Array/
/// null, recursively. Exists for exactly one purpose: the V2 home feed's
/// section `data[]` array holds a different row shape depending on that
/// section's `viewType` (`HOME_V2_API.md` §4's catalogue) — a value only
/// known once the envelope around it has already started decoding, so the
/// rows can't be typed as `[SongDTO]` (or any other concrete DTO) up front.
/// Decoding into `[JSONValue]` first, then re-encoding just that slice back
/// to `Data` and decoding it a second time as the concrete row type once the
/// caller knows which one applies (`HomeSectionContentDecoder`), keeps every
/// DTO's decode itself plain compiler-synthesized `Codable` — no hand-written
/// `Decoder`/`Any`-typed traversal to get subtly wrong with no compiler here
/// to check it.
enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
