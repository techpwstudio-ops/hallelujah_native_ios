import SwiftUI

/// T54 (Bible reader) — the Read tab's root content (wired later by a
/// deferred `AppShellView` patch as `case .read: ReaderView()`, the same
/// no-parameter tab-root shape as `HomeView()`/`BrowseView()`; `AppShellView`
/// is on the forbidden-to-edit list, so that wiring isn't done here).
///
/// Layout: a top bar (current book name / "chapter/maxChapters" / language /
/// font-size-and-theme), a transient boundary-message banner, then the
/// chapter body — previous/next chapter chevrons flanking a scrollable
/// `LazyVStack` of `VerseRowView`, one per `viewModel.verses`, exactly as
/// the locked contract's layout instruction describes. `.back`/
/// `.chevronForward` (checked `IconToken.swift` first, per the contract's
/// hard rule — both already exist) stand in for the previous/next chapter
/// chevrons; no raw SF Symbol fallback was needed for either direction.
///
/// Sheet wiring follows the *actual* convention its sibling components
/// (`BookTableOfContentsSheet`/`ChapterGridSheet`/`LanguagePickerSheet`/
/// `ReaderPreferencesSheet`, already on disk from Agent D) document for
/// themselves: each is bare content built for `.appSheet(isPresented:)`
/// (`AppSheet.swift`) — the shared glass-chrome + drag-handle container,
/// the same convention `PhoneAuthView` uses for `CountryPickerView` — not
/// the plain SwiftUI `.sheet`. `MyNotesView`/`VerseNoteEditorSheet` (also
/// already on disk, from Agent E) are the opposite: each owns its own
/// `NavigationStack`/background/toolbar, and their own doc comments say
/// plain `.sheet(isPresented:)`/`.sheet(item:)` — so that's what's used for
/// those two here. This is a deliberate deviation from the locked
/// contract's own generic "`.sheet(isPresented:)`" wording for the first
/// four, in favor of matching the real, already-written sibling files —
/// the contract's own "match this codebase's real conventions exactly"
/// hard rule takes precedence over a paraphrase.
///
/// The verse note editor's own presentation state
/// (`noteEditorVerse: BibleVerse?`) isn't one of the 5 `show*` flags the
/// locked contract names explicitly, but is needed to route
/// `VerseRowView`'s "Note" context-menu action to `VerseNoteEditorSheet`
/// (whose own doc comment says exactly this call site) — added the same
/// way as the other presentation flags, keyed on the tapped verse itself
/// (`BibleVerse` is `Identifiable`) so `.sheet(item:)` can drive it.
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @State private var showTableOfContents = false
    @State private var showChapterGrid = false
    @State private var showLanguagePicker = false
    @State private var showPreferences = false
    @State private var showMyNotes = false
    @State private var showBibleSearch = false
    @State private var noteEditorVerse: BibleVerse?
    @State private var askEmetVerse: BibleVerse?
    @State private var readAloud = ReadAloudController()
    /// T56 — resolved once (not per-render) so `ReaderNavigationStore`'s
    /// shared instance is captured, matching `AIChatNavigationStore`'s own
    /// call-site convention.
    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if readAloud.activeKey != nil {
                ListenControlBar(
                    status: readAloud.status,
                    progress: readAloud.progress,
                    isRestarting: readAloud.isRestarting,
                    onTogglePlayPause: readAloud.togglePlayPause,
                    onSeek: { readAloud.seek(toFraction: $0) },
                    onStop: { readAloud.stop() }
                )
            }
            if let boundaryMessage = viewModel.boundaryMessage {
                boundaryBanner(boundaryMessage)
            }
            content
        }
        .background(theme.color(.backgroundPrimary))
        .animation(.default, value: viewModel.boundaryMessage)
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: viewModel.currentChapterNumber) { _, _ in
            readAloud.stop()
        }
        // T56 — a verse-of-day tap/push/deep link can set `pendingTarget`
        // before or after this view's own book list has finished loading
        // (unlike `AIChatNavigationStore.pendingConversationID`, consuming
        // it needs `viewModel.books` to already be populated), so both
        // orderings are watched rather than just the one `.onChange` other
        // navigation-store consumers use.
        .onChange(of: viewModel.state) { _, _ in consumePendingTarget() }
        .onChange(of: navigationStore.pendingTarget) { _, _ in consumePendingTarget() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("My Notes") { showMyNotes = true }
                } label: {
                    theme.icon(.more)
                }
            }
        }
        .appSheet(isPresented: $showTableOfContents) {
            BookTableOfContentsSheet(books: viewModel.books) { book in
                viewModel.select(book: book)
            }
        }
        .appSheet(isPresented: $showChapterGrid) {
            if let book = viewModel.currentBook {
                ChapterGridSheet(book: book, currentChapter: viewModel.currentChapterNumber) { chapterNumber in
                    viewModel.select(chapterNumber: chapterNumber)
                }
            }
        }
        .appSheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(languages: viewModel.languages, currentLanguage: viewModel.currentLanguage) { language in
                viewModel.select(language: language)
            }
        }
        .appSheet(isPresented: $showPreferences) {
            ReaderPreferencesSheet(
                preferences: viewModel.preferences,
                onFontSizeChange: { viewModel.setFontSize($0) },
                onThemeChange: { viewModel.setTheme($0) }
            )
        }
        // T55 — verse/content/book search within `viewModel.currentLanguage`.
        // Both taps reuse `select(bookNumber:chapterNumber:)` (added for
        // T56's `ReaderNavigationStore` above), the one dispatch that jumps
        // straight to an arbitrary book/chapter in a single load.
        .appSheet(isPresented: $showBibleSearch) {
            BibleSearchSheet(
                languageName: viewModel.currentLanguage,
                onVerseTap: { result in
                    viewModel.select(bookNumber: result.bookNumber, chapterNumber: result.chapterNumber)
                },
                onBookTap: { book in
                    viewModel.select(bookNumber: book.bookNumber, chapterNumber: 1)
                }
            )
        }
        // Plain `.sheet`, not `.appSheet` — `MyNotesView` owns its own
        // `NavigationStack`/background/"Done" toolbar (see its doc
        // comment), unlike the 4 bare-content sheets above. Passes
        // `viewModel.books` so it can resolve each note's book name
        // locally, per the contract. Not `coordinator.push(...)`: no
        // `AppRoute` case exists for "open my notes", and adding one to
        // `AppRoute.swift` is forbidden here.
        .sheet(isPresented: $showMyNotes) {
            MyNotesView(books: viewModel.books)
        }
        // Also a plain `.sheet`, keyed on the tapped verse — see this
        // type's own doc comment.
        .sheet(item: $noteEditorVerse) { verse in
            VerseNoteEditorSheet(
                verse: verse,
                existingNote: viewModel.notesByVerseID[verse.id],
                onSave: { content in
                    Task { await viewModel.saveNote(verseID: verse.id, content: content) }
                },
                onDelete: {
                    Task { await viewModel.deleteNote(verseID: verse.id) }
                }
            )
        }
        // Also a plain `.sheet(item:)`, mirroring `noteEditorVerse` above —
        // T60's "Ask Emet about this verse" entry point.
        .sheet(item: $askEmetVerse) { verse in
            AIVerseInsightDialogView(
                target: .fromBibleVerse(verse, bookName: viewModel.currentBook?.name, languageName: viewModel.currentLanguage)
            )
        }
    }

    // MARK: - Navigation store

    /// See the `.onChange` pair above for why this is reached from two
    /// different triggers.
    private func consumePendingTarget() {
        guard viewModel.state == .loaded, let target = navigationStore.pendingTarget else { return }
        navigationStore.pendingTarget = nil
        viewModel.select(bookNumber: target.bookNumber, chapterNumber: target.chapterNumber)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            Button {
                showTableOfContents = true
            } label: {
                Text(viewModel.currentBook?.name ?? "Select Book")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                showChapterGrid = true
            } label: {
                Text("\(viewModel.currentChapterNumber)/\(viewModel.maxChapters)")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentBook == nil)

            Spacer(minLength: 0)

            // T55 — search within the current language's Bible content
            // (`BibleSearchSheet`), distinct from `showLanguagePicker`'s own
            // language-list search below it.
            Button {
                showBibleSearch = true
            } label: {
                theme.icon(.search)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)

            // No `IconToken` case for a globe/language glyph (checked
            // `IconToken.swift` first, per the contract's hard rule) — raw
            // SF Symbol, per the contract's own explicit instruction.
            Button {
                showLanguagePicker = true
            } label: {
                Image(systemName: "globe")
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)

            // No `IconToken` case for a font-size glyph either — same
            // reasoning, also per the contract's own explicit instruction.
            Button {
                showPreferences = true
            } label: {
                Image(systemName: "textformat.size")
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)

            // No `IconToken` case for a speaker/listen glyph either — same
            // reasoning. Toggles `ReadAloudController` on the current
            // chapter; tapping again while already reading this chapter
            // toggles play/pause (see `ReadAloudController.toggle(key:...)`).
            Button {
                toggleReadAloud()
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentBook == nil)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Boundary banner

    /// A simple transient inline banner (the contract's other option, an
    /// `.alert`, would demand an explicit dismiss tap for what Dart treats
    /// as a fire-and-forget toast) — auto-clears itself via `.task(id:)`
    /// keyed on the message text, so a fresh boundary message re-arms its
    /// own timer independently of any previous one.
    private func boundaryBanner(_ message: String) -> some View {
        Text(message)
            .typography(Typography.bodySmall)
            .foregroundStyle(theme.color(.textOnBrand))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(theme.color(.brandPrimary))
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(2))
                viewModel.clearBoundaryMessage()
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
                .frame(maxHeight: .infinity)
        case .failed:
            // `.refresh()`, not `.loadIfNeeded()`: `ReaderViewModel`'s own
            // `loadIfNeeded()` guards on `state == .loading`, so once
            // `state` has flipped to `.failed` it would be a permanent
            // no-op here — `refresh()` is the one that actually re-issues
            // a request, matching `UserPlaylistDetailView`'s own
            // `ErrorStateView` retry convention.
            ErrorStateView(
                title: "Couldn't load the reader",
                onRetry: { Task { await viewModel.refresh() } }
            )
            .frame(maxHeight: .infinity)
        case .loaded:
            chapterBody
        }
    }

    private var chapterBody: some View {
        HStack(spacing: 0) {
            chevronButton(.back, action: viewModel.goToPreviousChapter)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(viewModel.verses) { verse in
                        VerseRowView(
                            verse: verse,
                            highlightColorHex: viewModel.highlightsByVerseID[verse.id]?.colorHex,
                            hasNote: viewModel.notesByVerseID[verse.id] != nil,
                            fontSize: viewModel.preferences.fontSize,
                            theme: viewModel.preferences.theme,
                            onHighlight: { hex in
                                Task { await viewModel.toggleHighlight(verseID: verse.id, colorHex: hex) }
                            },
                            onRemoveHighlight: {
                                Task { await viewModel.removeHighlight(verseID: verse.id) }
                            },
                            onOpenNote: { noteEditorVerse = verse },
                            onShare: { Task { await share(verse: verse) } },
                            onAskEmet: { askEmetVerse = verse }
                        )
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
            .overlay(alignment: .top) {
                if viewModel.isChapterLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, Spacing.xs)
                }
            }

            chevronButton(.chevronForward, action: viewModel.goToNextChapter)
        }
    }

    private func chevronButton(_ icon: IconToken, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            theme.icon(icon)
                .foregroundStyle(theme.color(.textSecondary))
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Listen

    /// Starts (or toggles play/pause on) `ReadAloudController` for the
    /// currently displayed chapter. Key format matches
    /// `ReadAloudController`'s own doc comment.
    private func toggleReadAloud() {
        guard let book = viewModel.currentBook else { return }
        readAloud.toggle(
            key: "\(book.bookNumber)-\(viewModel.currentChapterNumber)-\(viewModel.currentLanguage)",
            verses: viewModel.verses,
            languageName: viewModel.currentLanguage
        )
    }

    // MARK: - Share

    /// Drives the pre-existing, already-declared `AppRoute` case
    /// `.bibleVerseShare(verseReference:verseText:deepLinkURL:)` —
    /// `VerseRowView`'s "Share" context-menu action is the only
    /// user-triggered entry point into it anywhere in this feature.
    /// `verseReference`/`verseText` are built client-side from the
    /// already-loaded `BibleBook.name` + `BibleVerse`, per the locked
    /// contract, rather than parsing the server's `title`/`description`
    /// strings — only `link` is used from `GET /book/verse/share/:id`'s
    /// response (`BibleRepository.shareVerse(id:)`).
    private func share(verse: BibleVerse) async {
        guard let url = await viewModel.shareURL(for: verse), let book = viewModel.currentBook else { return }
        let reference = "\(book.name) \(viewModel.currentChapterNumber):\(verse.verseNumber)"
        coordinator.push(.bibleVerseShare(verseReference: reference, verseText: verse.text, deepLinkURL: url.absoluteString))
    }
}
