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
    private static let cardHeight: CGFloat = 200

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
    private static func formattedDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let date = Date.parseFlexibleISO8601(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func verseOfDayCard(_ payload: VerseOfDayPayload) -> some View {
        ZStack(alignment: .bottomLeading) {
            background(for: payload)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(theme.color(.brandPrimary))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let title = payload.title, !title.isEmpty {
                        Text(title)
                            .typography(Typography.labelMedium)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(payload.reference)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(.white)
                    Text(payload.verseText)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(4)
                    if let dateText = Self.formattedDate(payload.date) {
                        Text(dateText)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(Spacing.md)
        }
        .frame(height: Self.cardHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// `ArtworkView` (`DesignSystem/Components/Media/ArtworkView.swift`) is
    /// this codebase's existing async-image component (see
    /// `UserPlaylistDetailView.swift`'s header for the same
    /// `GeometryReader`-for-actual-width usage this mirrors). Its own `url`
    /// is an already-resolved `URL?`, not a CDN-relative path routed through
    /// `ArtworkURLResolver` — `backgroundImage` here is a plain wire URL
    /// string, not a variant-aware content asset — so it's turned into a
    /// `URL` directly.
    @ViewBuilder
    private func background(for payload: VerseOfDayPayload) -> some View {
        if let backgroundImage = payload.backgroundImage, let url = URL(string: backgroundImage) {
            GeometryReader { proxy in
                ArtworkView(url: url, width: proxy.size.width, height: Self.cardHeight, cornerRadius: 0, contentMode: .fill)
            }
        } else {
            theme.color(.surfaceSecondary)
        }
    }
}
