import SwiftUI

/// `ReadPage` (`lib/views/read/read_page.dart`) — the Read tab.
///
/// Layout (all values from the Dart widget tree):
/// - App bar (56pt): "Bible" titleLarge w600, left aligned, with a 20pt search
///   icon and a vertical "more" icon; search swaps it for a 44pt #333333
///   field (12pt radius) with a close button and a dropdown panel
///   (`BibleSearchPanel`) over a 60% black scrim.
/// - Body: the chapter's verses (`VerseRowView`, padded 20 horizontally, top
///   and bottom edges softly masked like `CustomShadedMask`) scroll full
///   width, with a floating glass row laid over their bottom edge — book name
///   + up chevron (opens the table of contents), prev/next chevrons around
///   "n/max" (opens the chapter grid). The row is the size of the system tab
///   bar under it, so verses scroll behind it, and the list ends with enough
///   padding to scroll the last verse clear of it.
/// - Loading / failed / empty chapter states: a spinner, or "Something went
///   wrong please check your network" with a Retry button.
/// - Chapter boundaries toast "This is first chapter" / "This is last chapter".
///
/// There is no pull-to-refresh, font-size/theme sheet or read-aloud in the
/// Flutter reader, so none is exposed here (their files remain unused).
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @State private var searchViewModel = BibleSearchViewModel()
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    @State private var showMenu = false
    /// What the menu sheet is showing. Language, Notes and Verse of the day
    /// slide in inside the same sheet (like books -> chapters in the table of
    /// contents) instead of closing it and opening a second sheet.
    @State private var menuPage: MenuPage = .menu
    @State private var showTableOfContents = false
    /// The book whose chapters the table-of-contents sheet is showing; `nil`
    /// shows the book list.
    @State private var tocChapterBook: BibleBook?

    private static let bookPickerAnimation = Animation.easeInOut(duration: 0.25)

    /// The table of contents' height, or the chapter grid's for its book.
    /// Changing it while the sheet is up animates the sheet to the new size.
    private var bookPickerDetent: PresentationDetent {
        guard let book = tocChapterBook else { return .fraction(0.75) }
        return .height(ChapterGridSheet.sheetHeight(
            chapterCount: book.chapters,
            width: windowSize.width,
            screenHeight: windowSize.height
        ))
    }
    @State private var noteEditorVerse: BibleVerse?
    @State private var askEmetVerse: AskEmetSelection?
    @State private var highlightPaletteVerse: HighlightSelection?
    /// The full-bleed page's size (the screen on a phone), for the chapter
    /// grid's detent.
    @State private var windowSize: CGSize = .zero

    @State private var navigationStore: ReaderNavigationStore = DependencyContainer.current.resolve()
    @State private var offlineService: BibleOfflineDownloadService = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    // The bottom row matches the system tab bar below it (iOS 26 floating bar,
    // measured on a 402pt-wide iPhone): 62pt tall, inset 21pt from each edge.
    // The tab bar / mini player inset already reserve the space under it.
    private static let bottomBarHeight: CGFloat = 62
    private static let bottomBarSideInset: CGFloat = 21
    private static let bottomBarGap: CGFloat = Spacing.sm
    /// Scroll room under the last verse so it can clear the floating row.
    private static let versesBottomClearance: CGFloat = bottomBarHeight + bottomBarGap + Spacing.md

    var body: some View {
        ZStack {
            ReadPalette.background
                // Measured here rather than read from `UIScreen`, which is the
                // whole display in Split View and on a Mac (native-only
                // tablet/Mac adaptation).
                .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if isSearching {
                    searchAppBar
                } else {
                    defaultAppBar
                }

                ZStack {
                    bodyContent

                    if isSearching && hasSearchPanelContent {
                        searchOverlay
                    }

                    if highlightPaletteVerse != nil {
                        highlightPalette
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadIfNeeded() }
        // `OurSession` caches the default Bible language silently after login.
        .task { await offlineService.ensureDefaultLanguageCached() }
        // A verse-of-day tap/push/deep link can set `pendingTarget` before or
        // after the book list has loaded, so both orderings are watched.
        .onChange(of: viewModel.state) { _, _ in consumePendingTarget() }
        .onChange(of: viewModel.isChapterLoading) { _, loading in
            if !loading { viewModel.healEmptyChapterIfNeeded() }
        }
        .onChange(of: navigationStore.pendingTarget) { _, _ in consumePendingTarget() }
        .onChange(of: viewModel.boundaryMessage) { _, message in
            guard let message else { return }
            toastCenter.show(message)
            viewModel.clearBoundaryMessage()
        }
        .sheet(isPresented: $showMenu, onDismiss: { menuPage = .menu }) {
            ReadSheetContainer {
                ZStack {
                    menuSheetPage
                }
                .clipped()
            }
            .presentationDetents([menuDetent])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(ReadPalette.sheetBackground)
        }
        // Books and chapters share one sheet, like Flutter's table of
        // contents: picking a book swaps the grid in place (and resizes the
        // sheet) instead of closing this sheet and opening a second one.
        .sheet(isPresented: $showTableOfContents, onDismiss: { tocChapterBook = nil }) {
            ReadSheetContainer {
                ZStack {
                    if let book = tocChapterBook {
                        ChapterGridSheet(
                            book: book,
                            language: viewModel.currentLanguage,
                            currentChapter: viewModel.currentChapterNumber,
                            currentBookNumber: viewModel.currentBook?.bookNumber,
                            onBack: {
                                withAnimation(Self.bookPickerAnimation) { tocChapterBook = nil }
                            },
                            onSelect: { chapter in
                                showTableOfContents = false
                                viewModel.select(bookNumber: book.bookNumber, chapterNumber: chapter)
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    } else {
                        BookTableOfContentsSheet(
                            books: viewModel.books,
                            currentBookNumber: viewModel.currentBook?.bookNumber,
                            language: viewModel.currentLanguage
                        ) { book in
                            withAnimation(Self.bookPickerAnimation) { tocChapterBook = book }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
                .clipped()
            }
            .presentationDetents([bookPickerDetent])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(16)
            .presentationBackground(ReadPalette.sheetBackground)
        }
        .readSheet(item: $noteEditorVerse, detents: [.large]) { verse in
            VerseNoteEditorSheet(
                verse: verse,
                bookName: viewModel.currentBook?.name ?? "",
                existingNote: viewModel.notesByVerseID[verse.id],
                onSave: { content in
                    Task { await viewModel.saveNote(verseID: verse.id, content: content) }
                },
                onDelete: {
                    Task { await viewModel.deleteNote(verseID: verse.id) }
                }
            )
        }
        .fullScreenCover(item: $askEmetVerse) { verse in
            AIVerseInsightDialogView(
                target: .fromBibleVerse(verse.verse, bookName: viewModel.currentBook?.translate(viewModel.currentLanguage), languageName: viewModel.currentLanguage),
                selectedText: verse.selectedText
            )
        }
    }

    /// The words a long-press selection picked in `verse`, awaiting a colour.
    private struct HighlightSelection: Identifiable {
        let verse: BibleVerse
        let indices: [Int]
        var id: String { verse.id }
    }

    /// "Ask Emet" for a verse, with the words that were selected (if any).
    private struct AskEmetSelection: Identifiable {
        let verse: BibleVerse
        let selectedText: String
        var id: String { verse.id }
    }

    private enum MenuPage: Equatable {
        case menu
        case language
        case notes
        case verseOfDay(id: String)
    }

    // MARK: - Navigation store

    private func consumePendingTarget() {
        guard viewModel.state == .loaded, let target = navigationStore.pendingTarget else { return }
        navigationStore.pendingTarget = nil
        viewModel.select(
            bookNumber: target.bookNumber,
            chapterNumber: target.chapterNumber,
            verseNumber: target.verseNumber
        )
    }

    // MARK: - App bars

    private var defaultAppBar: some View {
        HStack(spacing: 0) {
            Text("Bible")
                .readText(Typography.titleLarge, weight: .semibold)
                .padding(.leading, 16)
            Spacer(minLength: 0)
            GlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: openSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundStyle(ReadPalette.white)
                            .frame(width: 44, height: 44)
                            .glassCircle(interactive: true)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(ReadPalette.white)
                            .frame(width: 44, height: 44)
                            .glassCircle(interactive: true)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: 56)
    }

    private var searchAppBar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Dimens.paddingLarge)
            TextField(
                "",
                text: Binding(
                    get: { searchViewModel.queryText },
                    set: { searchViewModel.queryChanged($0, languageName: viewModel.currentLanguage) }
                ),
                prompt: Text("Search").foregroundColor(ReadPalette.grey)
            )
            .typography(Typography.bodyMedium)
            .foregroundStyle(ReadPalette.white)
            .tint(ReadPalette.logo)
            .submitLabel(.search)
            .focused($searchFocused)
            .autocorrectionDisabled()
            .onAppear { searchFocused = true }

            Button(action: onSearchTrailingTap) {
                Image(systemName: "xmark")
                    .font(.system(size: Dimens.iconSizeSmall + 4))
                    .foregroundStyle(ReadPalette.white60)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .glassCapsule(interactive: true)
        .padding(.horizontal, Dimens.screenPadding)
        // Native-only tablet/Mac adaptation: the same column as the results panel under it.
        .readableContentWidth()
        .frame(height: 56)
    }

    // MARK: - Search

    private var hasSearchPanelContent: Bool {
        searchViewModel.hasQuery || !searchViewModel.recent.isEmpty
    }

    private func openSearch() {
        isSearching = true
    }

    private func closeSearch() {
        searchFocused = false
        searchViewModel.reset()
        isSearching = false
    }

    /// Clears the field first, then closes search once it is empty.
    private func onSearchTrailingTap() {
        if !searchViewModel.queryText.isEmpty {
            searchViewModel.clearButtonTapped()
            searchFocused = true
        } else {
            closeSearch()
        }
    }

    private var searchOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.6)
                    .contentShape(Rectangle())
                    .onTapGesture { closeSearch() }

                BibleSearchPanel(
                    viewModel: searchViewModel,
                    maxHeight: proxy.size.height * 0.8,
                    onVerseTap: { result in
                        searchViewModel.recordTap(result)
                        closeSearch()
                        viewModel.select(
                            bookNumber: result.bookNumber,
                            chapterNumber: result.chapterNumber,
                            verseNumber: result.verseNumber
                        )
                    },
                    onBookTap: { book in
                        closeSearch()
                        viewModel.select(bookNumber: book.bookNumber, chapterNumber: 1)
                    }
                )
                // Absorb taps on the panel so it doesn't close the overlay.
                .onTapGesture {}
                // Native-only tablet/Mac adaptation: verse results in a
                // readable column, under the search field.
                .readableContentWidth()
            }
        }
    }

    // MARK: - Body

    private var bodyContent: some View {
        mainArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Over the list, not under it, so verses scroll behind the glass.
            .overlay(alignment: .bottom) {
                if viewModel.state == .loaded {
                    bottomBar
                }
            }
    }

    @ViewBuilder
    private var mainArea: some View {
        switch viewModel.state {
        case .loading:
            ReadSpinner()
        case .failed:
            if viewModel.books.isEmpty {
                VStack(spacing: 16) {
                    Text("Failed to load books")
                        .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body))
                        .foregroundStyle(ReadPalette.white)
                    retryButton
                }
                .padding(.horizontal, Dimens.spacing20)
            } else {
                emptyState
            }
        case .loaded:
            if viewModel.verses.isEmpty, viewModel.isChapterLoading || viewModel.isAutoHealing {
                ReadSpinner()
            } else if viewModel.verses.isEmpty {
                emptyState
                    .onAppear { viewModel.healEmptyChapterIfNeeded() }
            } else {
                // The chapter on screen stays up while the next one loads
                // (swapping it for a full-screen spinner was the "blink"),
                // then the new one slides in from the side it was asked for.
                ZStack {
                    verseList
                        .id(viewModel.chapterKey)
                        .transition(.push(from: viewModel.chapterTransitionEdge))
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.chapterKey)
                .overlay(alignment: .top) {
                    if viewModel.isChapterLoading {
                        ProgressView()
                            .tint(ReadPalette.white)
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ReadEmptyText(text: "Something went wrong please check your network")
            Spacer().frame(height: 16)
            retryButton
        }
        .padding(.horizontal, Dimens.spacing20)
    }

    private var retryButton: some View {
        Button {
            Task { await viewModel.retry() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                Text("Retry")
                    .readText(Typography.labelLarge)
            }
            .foregroundStyle(ReadPalette.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var verseList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.verses) { verse in
                        VerseRowView(
                            verse: verse,
                            highlight: viewModel.highlightsByVerseID[verse.id],
                            noteContent: viewModel.notesByVerseID[verse.id]?.content,
                            isFocused: viewModel.focusedVerse == verse.verseNumber,
                            onRequestHighlight: { highlightPaletteVerse = HighlightSelection(verse: verse, indices: $0) },
                            onRemoveHighlight: { indices in
                                Task { await viewModel.removeHighlight(verse: verse, indices: indices) }
                            },
                            onOpenNote: { noteEditorVerse = verse },
                            onShare: { Task { await share(verse: verse) } },
                            onAskEmet: { askEmetVerse = AskEmetSelection(verse: verse, selectedText: $0) }
                        )
                        .id(verse.verseNumber)
                    }
                }
                .padding(.horizontal, Dimens.spacing20)
                .padding(.top, 12)
                .padding(.bottom, Self.versesBottomClearance)
                // Native-only tablet/Mac adaptation: Bible text in a readable
                // column; the scroll view, mask and chrome stay full width.
                .readableContentWidth()
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: Color.black, location: 0.02),
                        .init(color: Color.black, location: 0.98),
                        .init(color: Color.clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: viewModel.scrollTargetVerse) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    // MARK: - Bottom row

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                showTableOfContents = true
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.currentBook?.translate(viewModel.currentLanguage) ?? "Loading...")
                        .readText(Typography.titleMedium, weight: .bold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReadPalette.white)
                        .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer().frame(width: 8)

            HStack(spacing: 0) {
                navIcon(systemName: "chevron.left") {
                    viewModel.goToPreviousChapter()
                }
                Button {
                    if let book = viewModel.currentBook {
                        tocChapterBook = book
                        showTableOfContents = true
                    }
                } label: {
                    Text("\(viewModel.currentChapterNumber)/\(viewModel.maxChapters)")
                        .readText(Typography.titleLarge, weight: .bold, color: ReadPalette.secondaryText)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                navIcon(systemName: "chevron.right") {
                    viewModel.goToNextChapter()
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Self.bottomBarHeight)
        .glassCapsule()
        // Taps on the row's empty space must not fall through to verses behind.
        .contentShape(Capsule())
        .padding(.horizontal, Self.bottomBarSideInset)
        // Same gap as between the mini player and the tab bar.
        .padding(.bottom, Self.bottomBarGap)
    }

    private func navIcon(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReadPalette.white)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isChapterLoading)
    }

    // MARK: - Highlight palette

    /// Flutter's white colour popup (`_showColorsPalate`): a collapse chevron,
    /// then the four `bookHighlightColors` as 20pt dots split by dividers.
    private var highlightPalette: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { highlightPaletteVerse = nil }

            HStack(spacing: 0) {
                Button {
                    highlightPaletteVerse = nil
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ReadPalette.black)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                ForEach(Array(ReadPalette.highlightHexes.enumerated()), id: \.offset) { index, hex in
                    Button {
                        if let selection = highlightPaletteVerse {
                            Task { await viewModel.applyHighlight(verse: selection.verse, indices: selection.indices, colorHex: hex) }
                        }
                        highlightPaletteVerse = nil
                    } label: {
                        Circle()
                            .fill(Color(readHex: hex) ?? ReadPalette.white)
                            .frame(width: 20, height: 20)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)

                    if index != ReadPalette.highlightHexes.count - 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 1, height: 24)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ReadPalette.white)
            )
        }
    }

    // MARK: - Menu sheet (`showBookPageMainMenu`)

    /// Each page's height; changing it while the sheet is up animates the
    /// sheet to the new size, as the table of contents does.
    private var menuDetent: PresentationDetent {
        switch menuPage {
        case .menu: return .height(300)
        case .language: return .fraction(0.85)
        case .notes: return .fraction(0.9)
        case .verseOfDay: return .fraction(0.95)
        }
    }

    private func showMenuPage(_ page: MenuPage) {
        withAnimation(Self.bookPickerAnimation) { menuPage = page }
    }

    private static let menuPushTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    @ViewBuilder
    private var menuSheetPage: some View {
        switch menuPage {
        case .menu:
            menuSheet
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .language:
            LanguagePickerSheet(
                languages: viewModel.languages,
                currentLanguage: viewModel.currentLanguage,
                onBack: { showMenuPage(.menu) }
            ) { language in
                showMenu = false
                // `OurSession.changeReadLanguage`: persist on the account, fire-and-forget.
                Task { await ReadLanguageSaver().save(language: language) }
                viewModel.select(language: language)
            }
            .transition(Self.menuPushTransition)
        case .notes:
            MyNotesView(
                books: viewModel.books,
                currentLanguage: viewModel.currentLanguage,
                onSelect: { entry in
                    showMenu = false
                    viewModel.select(
                        bookNumber: entry.bookNumber,
                        chapterNumber: entry.chapterNumber,
                        verseNumber: entry.verseNumber
                    )
                },
                onBack: { showMenuPage(.menu) }
            )
            .transition(Self.menuPushTransition)
        case .verseOfDay(let id):
            VerseOfDayCommentsSheet(verseOfDayId: id, showsVerseOfDay: true, onBack: { showMenuPage(.menu) })
                .transition(Self.menuPushTransition)
        }
    }

    private var menuSheet: some View {
        VStack(spacing: 0) {
            ReadDragHandle()

            menuRow(icon: "globe", title: "Language", trailing: {
                HStack(spacing: 0) {
                    Text(viewModel.state == .loaded ? viewModel.currentLanguage : "-")
                        .readText(Typography.titleMedium, weight: .medium, color: ReadPalette.tertiaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReadPalette.white)
                        .frame(width: 24, height: 24)
                }
            }) {
                showMenuPage(.language)
            }

            if !viewModel.currentLanguage.isEmpty {
                menuRow(icon: "arrow.down.circle", title: "Offline Bible", trailing: {
                    BibleOfflineDownloadButton(language: viewModel.currentLanguage)
                }) {
                    let language = viewModel.currentLanguage
                    Task {
                        await startBibleOfflineDownload(language: language, service: offlineService, toast: toastCenter)
                    }
                }
            }

            menuRow(icon: "note.text", title: "Notes", trailing: { EmptyView() }) {
                showMenuPage(.notes)
            }

            menuRow(icon: "book", title: "Verse of the day", trailing: { EmptyView() }) {
                openVerseOfDay()
            }

            Spacer().frame(height: 16)
        }
    }

    private func menuRow<Trailing: View>(
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing,
        action: @escaping () -> Void
    ) -> some View {
        let trailingView = trailing()
        return Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(ReadPalette.white)
                    .frame(width: 24, height: 24)
                Text(title)
                    .readText(Typography.titleMedium, weight: .medium)
                Spacer(minLength: 0)
                trailingView
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Verse of the day" menu row: the latest verse's comments, with the
    /// verse card on top, slide in; a toast when none has ever been delivered.
    private func openVerseOfDay() {
        let container = DependencyContainer.current
        let keyValueStore: any KeyValueStoring = container.resolve()
        let localStore = VerseOfDayLocalStore(keyValueStore: keyValueStore)
        guard let id = localStore.lastVerseOfDayID else {
            toastCenter.show("There is no verse of day for today.")
            return
        }
        showMenuPage(.verseOfDay(id: id))
    }

    // MARK: - Share

    private func share(verse: BibleVerse) async {
        guard let url = await viewModel.shareURL(for: verse), let book = viewModel.currentBook else { return }
        let reference = "\(book.name) \(viewModel.currentChapterNumber):\(verse.verseNumber)"
        coordinator.push(.bibleVerseShare(verseReference: reference, verseText: verse.text, deepLinkURL: url.absoluteString))
    }
}
