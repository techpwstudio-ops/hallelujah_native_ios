import SwiftUI

/// T58 — renders one `AIToolResult` from the tool-data embedding protocol
/// (`AIMessage.parseRawContent(raw:)`, `App/Domain/Entities/AIChatModels.swift`).
/// A dispatcher keyed on `toolResult.name`: only `getVerseOfDay` is a
/// recognized tool today. Any other/unrecognized name — and a `getVerseOfDay`
/// payload that doesn't decode as expected, or decodes with `found == false`
/// — renders nothing (`EmptyView`), never a broken card. Do not add branches
/// for other tool names speculatively; only `getVerseOfDay` exists today.
struct AIToolResultCard: View {
    let toolResult: AIToolResult

    @Environment(\.appTheme) private var theme

    private static let toolName = "getVerseOfDay"

    var body: some View {
        if toolResult.name == Self.toolName,
           let payload = Self.decodePayload(toolResult.result),
           payload.found {
            verseOfDayCard(payload)
        } else {
            EmptyView()
        }
    }

    // MARK: - getVerseOfDay

    /// `{ found: Bool, reference: String, verseText: String, title: String?,
    /// date: String?, backgroundImage: String? }`. `JSONValue` is itself
    /// `Codable` (`Core/Networking/Models/JSONValue.swift`), so the same
    /// "re-encode the dynamic slice, decode it a second time as a concrete
    /// type" technique that file's own header comment describes for the V2
    /// home feed applies here too — no hand-written `JSONValue` case
    /// traversal, and no new dynamic-JSON type invented for this.
    private struct VerseOfDayPayload: Decodable {
        let found: Bool
        let reference: String
        let verseText: String
        let title: String?
        let date: String?
        let backgroundImage: String?
    }

    private static func decodePayload(_ result: JSONValue) -> VerseOfDayPayload? {
        guard let data = try? JSONEncoder().encode(result) else { return nil }
        return try? JSONDecoder().decode(VerseOfDayPayload.self, from: data)
    }

    /// `Date.parseFlexibleISO8601` (`Core/Extensions/Foundation/
    /// Date+FlexibleISO8601.swift`) already covers the ISO 8601 case; a
    /// `date` that doesn't parse as one still renders — verbatim, rather than
    /// hiding an otherwise-valid card over a formatting miss.
    /// Mirrors Dart's manual `_formatDate`: `Mon d, yyyy` in local time; null on parse failure.
    private static func formattedDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let date = Date.parseFlexibleISO8601(raw) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static let cardRadius: CGFloat = 16

    private func verseOfDayCard(_ payload: VerseOfDayPayload) -> some View {
        let hasBackground = !(payload.backgroundImage ?? "").isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AIColors.gold)
                Text("Verse of the Day")
                    .font(AIColors.font(11, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AIColors.gold)
                if let dateText = Self.formattedDate(payload.date) {
                    Spacer(minLength: 0)
                    Text(dateText)
                        .font(AIColors.font(10))
                        .foregroundStyle(AIColors.white54)
                }
            }

            Text(payload.reference)
                .font(AIColors.font(18, .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.white)
                .padding(.top, 10)

            if let title = payload.title, !title.isEmpty {
                Text(title)
                    .font(AIColors.font(12, .medium))
                    .foregroundStyle(AIColors.gold.opacity(0.85))
                    .padding(.top, 2)
            }

            if !payload.verseText.isEmpty {
                Rectangle()
                    .fill(AIColors.white24)
                    .frame(height: 0.5)
                    .padding(.top, 10)
                Text("\"\(payload.verseText)\"")
                    .font(AIColors.font(14))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineSpacing(14 * (1.6 - 1.15))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                if hasBackground {
                    background(for: payload)
                }
                LinearGradient(
                    colors: hasBackground
                        ? [Color.black.opacity(0.72), Color.black.opacity(0.60)]
                        : [Color(red: 0x2A / 255, green: 0x1F / 255, blue: 0x0A / 255),
                           Color(red: 0x1A / 255, green: 0x14 / 255, blue: 0x08 / 255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle()
                    .fill(AIColors.gold)
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius - 0.8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .strokeBorder(AIColors.gold.opacity(0.4), lineWidth: 0.8)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func background(for payload: VerseOfDayPayload) -> some View {
        if let backgroundImage = payload.backgroundImage,
           let url = ArtworkURLResolver().resolve(path: backgroundImage, variant: .lg, allowedVariants: nil) {
            GeometryReader { proxy in
                ArtworkView(url: url, width: proxy.size.width, height: proxy.size.height, cornerRadius: 0, contentMode: .fill)
            }
        }
    }
}
