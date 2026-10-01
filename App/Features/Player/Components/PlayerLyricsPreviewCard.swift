import SwiftUI

/// T35 — ports `SongLyricsDetails` (`lib/widgets/player/lyrics_ui.dart`):
/// a glass card shown only when the current song has transcripts, holding
/// a non-interactive, position-synced lyrics preview plus a button to the
/// real lyrics screen. `AbsorbPointer` (Dart) maps to `.scrollDisabled(true)`
/// here — the preview auto-scrolls with playback, it never takes a manual
/// scroll gesture of its own. `SongLyricsPage` itself (`lib/views/home/
/// SongLyricsPage.dart`) is T36's screen — this pushes the already-existing
/// `PlayerRoute.lyrics` placeholder, same "T35 supplies the entry point"
/// split already used for the queue button.
struct PlayerLyricsPreviewCard: View {
    @Environment(\.appTheme) private var theme
    let song: Song
    let currentPosition: TimeInterval
    let onViewFull: () -> Void

    private static let previewHeight: CGFloat = 220

    private var transcripts: [LyricsTranscript] { song.transcripts ?? [] }

    /// `_updateForSeconds` (`lib/widgets/player/lyrics_preview.dart`) and
    /// `SongLyricsPage._onPositionChanged` (`SongLyricsPage.dart:86-93`)
    /// both use `lines.lastIndexWhere((l) => l.start <= seconds)` — the
    /// LAST line whose start has passed, ignoring `end` entirely, so a
    /// line stays highlighted until the next one starts even past its own
    /// `end`. `first { start <= pos < end }` (the previous version of this
    /// property) is a different, un-ported range check.
    private var activeLineID: String? {
        transcripts.last { currentPosition >= $0.startTime }?.id
    }

    var body: some View {
        if !transcripts.isEmpty {
            GlassSurface(.regular, cornerRadius: Radius.xl) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Lyrics")
                        .typography(Typography.titleSmall)
                        .foregroundStyle(theme.color(.textPrimary))

                    preview

                    viewFullButton
                }
                .padding(Spacing.md)
            }
        }
    }

    private var preview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(transcripts) { line in
                        Text(line.text ?? "")
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(line.id == activeLineID ? theme.color(.textPrimary) : theme.color(.textSecondary))
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(true)
            .frame(height: Self.previewHeight)
            .onChange(of: activeLineID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var viewFullButton: some View {
        Button(action: onViewFull) {
            Text("View Full Lyrics")
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
        .background {
            Capsule(style: .continuous).strokeBorder(theme.color(.border), lineWidth: 1)
        }
    }
}
