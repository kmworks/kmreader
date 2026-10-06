#if os(iOS) || os(macOS)
  import SwiftUI

  struct PdfReaderView: View {
    let sessionID: UUID
    let book: Book
    let incognito: Bool
    let readerPresentation: ReaderPresentationManager
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("currentAccount") private var current: Current = .init()
    @AppStorage("pdfReaderBackground") private var readerBackground: ReaderBackground = .system
    @AppStorage("isOffline") private var isOffline: Bool = false
    @AppStorage("pdfDefaultReadingDirection")
    private var defaultReadingDirection: ReadingDirection = .ltr
    @AppStorage("pdfForceDefaultReadingDirection")
    private var forceDefaultReadingDirection: Bool = false
    @AppStorage("pdfShowKeyboardHelpOverlay")
    private var showKeyboardHelpOverlay: Bool = AppConfig.pdfShowKeyboardHelpOverlay
    @AppStorage("showPdfControlsGradientBackground")
    private var showControlsGradientBackground: Bool =
      AppConfig.showPdfControlsGradientBackground
    @AppStorage("showPdfProgressBarWhileReading")
    private var showProgressBarWhileReading: Bool =
      AppConfig.showPdfProgressBarWhileReading

    @State private var viewModel: PdfReaderViewModel
    @State private var readingDirection: ReadingDirection
    @State private var pagePresentation: PdfPagePresentation
    @State private var isolateCoverPage: Bool
    @State private var currentBook: Book?
    @State private var currentSeries: Series?
    @State private var showingControls = false
    // Captures `shouldShowControls` on the active → non-active scene-phase
    // transition (before the force-show below flips `showingControls`), so
    // the subsequent resume can decide whether to auto-hide the overlay or
    // leave it visible. See `handleScenePhaseChange(from:to:)`.
    @State private var wasShowingControlsBeforeBackground: Bool = false
    // Task that fades the resume-triggered overlay back to hidden after a
    // brief glance window. Reset on user interaction (page change) to act as
    // an idle timeout; cancelled on tap-toggle and reader close.
    @State private var autoHideAfterResumeTask: Task<Void, Never>?
    @State private var showingPageJumpSheet = false
    @State private var showingSearchSheet = false
    @State private var showingTOCSheet = false
    @State private var showingPreferencesSheet = false
    @State private var showingDetailSheet = false
    @State private var searchQuery = ""
    @State private var targetPageNumber: Int?
    @State private var navigationToken = UUID()
    @State private var keyboardHelpTimer: Timer?
    @State private var showKeyboardHelp = false

    private let logger = AppLogger(.reader)

    init(
      sessionID: UUID,
      book: Book,
      incognito: Bool = false,
      readerPresentation: ReaderPresentationManager,
      onClose: (() -> Void)? = nil
    ) {
      self.sessionID = sessionID
      self.book = book
      self.incognito = incognito
      self.readerPresentation = readerPresentation
      self.onClose = onClose
      _viewModel = State(initialValue: PdfReaderViewModel(incognito: incognito))
      _readingDirection = State(initialValue: .ltr)
      _pagePresentation = State(initialValue: AppConfig.pdfPagePresentation)
      _isolateCoverPage = State(initialValue: AppConfig.pdfIsolateCoverPage)
      _currentBook = State(initialValue: book)
    }

    private var isPresentingModalSheet: Bool {
      showingPageJumpSheet
        || showingSearchSheet
        || showingTOCSheet
        || showingPreferencesSheet
        || showingDetailSheet
    }

    private var isKeyboardCaptureEnabled: Bool {
      !isPresentingModalSheet
    }

    var body: some View {
      ZStack {
        readerBackground.color.readerIgnoresSafeArea()

        contentView

        controlsOverlay
          .simultaneousGesture(
            // Touching the controls (close button, title, ⋯ menu, page jump)
            // is explicit intent to keep the overlay: cancel the post-resume
            // auto-hide instead of letting it dismiss an open menu.
            TapGesture().onEnded { cancelAutoHideAfterResume() }
          )

        keyboardHelpOverlay
      }
      #if os(iOS)
        .statusBarHidden(!shouldShowControls)
      #endif
      .sheet(isPresented: $showingPageJumpSheet) {
        if let documentURL = viewModel.documentURL {
          PdfPageJumpSheetView(
            documentURL: documentURL,
            totalPages: viewModel.pageCount,
            currentPage: viewModel.currentPageNumber,
            readingDirection: readingDirection,
            onJump: { page in
              requestPageNavigation(to: page)
            }
          )
        }
      }
      .sheet(isPresented: $showingSearchSheet) {
        PdfSearchSheetView(
          query: $searchQuery,
          isSearching: viewModel.isSearching,
          results: viewModel.searchResults,
          onSearch: { query in
            runSearch(query: query)
          },
          onSelectResult: { result in
            requestPageNavigation(to: result.pageNumber)
          }
        )
      }
      .sheet(isPresented: $showingTOCSheet) {
        DivinaTOCSheetView(
          entries: viewModel.tableOfContents,
          currentEntryIDs: currentTOCSelection.entryIDs,
          scrollTargetID: currentTOCSelection.scrollTargetID,
          onSelect: { entry in
            showingTOCSheet = false
            requestPageNavigation(to: entry.pageIndex + 1)
          }
        )
      }
      .sheet(isPresented: $showingPreferencesSheet) {
        PdfReaderSettingsSheet()
      }
      .readerDetailSheet(
        isPresented: $showingDetailSheet,
        book: currentBook,
        series: currentSeries
      )
      .iPadIgnoresSafeArea()
      .task(id: book.id) {
        readerPresentation.registerFlushHandler(for: sessionID) {
          viewModel.flushProgress()
        }
        await loadBook()
      }
      .onAppear {
        updateHandoff()
        #if os(macOS)
          configureReaderCommands()
        #endif
      }
      .onChange(of: defaultReadingDirection) { _, newDirection in
        if newDirection == .webtoon {
          defaultReadingDirection = .vertical
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .fileDownloadProgress)) { notification in
        viewModel.updateDownloadProgress(notification: notification)
      }
      .onChange(of: currentBook) { _, newBook in
        if let newBook {
          readerPresentation.updatePresentedBook(sessionID: sessionID, book: newBook)
        }
        updateHandoff()
      }
      .onChange(of: viewModel.currentPageNumber) { _, _ in
        updateHandoff()
        // Treat page changes as user activity: if we're inside the post-
        // resume auto-hide window, restart the timer so the overlay stays
        // visible while the user is actively flipping pages and only fades
        // after a real pause.
        resetAutoHideAfterResumeIfPending()
      }
      .onChange(of: viewModel.documentURL) { _, newURL in
        guard newURL != nil else { return }
        guard viewModel.pageCount > 0 else { return }

        let targetPage = documentInitialPage
        DispatchQueue.main.async {
          forcePageNavigation(to: targetPage)
        }
      }
      .onDisappear {
        logger.debug(
          "👋 PDF reader disappeared for book \(book.id), page=\(viewModel.currentPageNumber)/\(viewModel.pageCount)"
        )
        showingControls = false
        #if os(macOS)
          hideKeyboardHelp()
        #endif
      }
      .onChange(of: scenePhase) { oldPhase, newPhase in
        handleScenePhaseChange(from: oldPhase, to: newPhase)
      }
      .onChange(of: isPresentingModalSheet) { _, presenting in
        // A sheet opening (menu action, keyboard command) is controls
        // interaction: the post-resume glance window ends here.
        if presenting {
          cancelAutoHideAfterResume()
        }
      }
      .background(
        KeyboardEventHandler(
          isEnabled: isKeyboardCaptureEnabled,
          commands: keyboardCommands,
          onKeyPress: handleKeyboardEvent
        )
      )
      .onChange(of: viewModel.pageCount) { oldCount, newCount in
        if oldCount == 0 && newCount > 0 {
          triggerKeyboardHelp(timeout: 1.5)
        }
      }
      #if os(macOS)
        .onChange(of: readerCommandState) { _, newState in
          readerPresentation.updateReaderCommandState(newState)
        }
      #endif
      #if os(iOS)
        .readerDismissGesture(readingDirection: readingDirection)
      #endif
    }

    private var shouldShowControls: Bool {
      if viewModel.errorMessage != nil { return true }
      if viewModel.isLoading { return true }
      return showingControls
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
      // Capture pre-background overlay state on the active → non-active edge,
      // BEFORE the force-show below flips `showingControls`. Tells the
      // subsequent resume whether to auto-hide the overlay or leave it
      // visible.
      if oldPhase == .active && newPhase != .active {
        wasShowingControlsBeforeBackground = autoHideAfterResumeTask == nil && shouldShowControls
        cancelAutoHideAfterResume()
      }

      // Force the overlay visible on every background → foreground cycle so
      // iOS's status-bar / safe-area state stays in a known configuration and
      // the dashboard inherits a clean safe-area on subsequent close. The
      // overlay flashing visible on every lock/unlock is what the auto-hide
      // below mitigates.
      if newPhase != .active || !shouldShowControls {
        showingControls = true
      }

      // On returning to .active: if pre-background was hidden, schedule a
      // brief auto-hide so the user gets a glance and the overlay fades back
      // to where it was.
      if oldPhase != .active, newPhase == .active, !wasShowingControlsBeforeBackground {
        scheduleAutoHideAfterResume()
      }

      #if os(iOS)
        // Flush in-flight read progress to the server before iOS suspends the app, so
        // the trailing pages of the reading session are not lost to URLSession cancellation.
        if newPhase == .background {
          readerPresentation.flushForBackgrounding()
        }
      #endif
    }

    /// Fade the overlay back to hidden after a brief glance window. Used only
    /// on the resume path when the user had the overlay hidden before going
    /// to background; preserves visible-overlay sessions untouched.
    private func scheduleAutoHideAfterResume() {
      autoHideAfterResumeTask?.cancel()
      autoHideAfterResumeTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        // Belt and braces: never pull the overlay out from under an open
        // sheet or menu interaction.
        guard !isPresentingModalSheet else {
          autoHideAfterResumeTask = nil
          return
        }
        withAnimation {
          showingControls = false
        }
        autoHideAfterResumeTask = nil
      }
    }

    private func cancelAutoHideAfterResume() {
      autoHideAfterResumeTask?.cancel()
      autoHideAfterResumeTask = nil
    }

    /// Restart the auto-hide timer if one is currently pending. Called from
    /// existing user-interaction observers (e.g., page changes) so the auto-
    /// hide acts as an idle timeout: interaction within the window resets
    /// the clock, and the overlay only fades when the user actually pauses.
    private func resetAutoHideAfterResumeIfPending() {
      guard autoHideAfterResumeTask != nil else { return }
      scheduleAutoHideAfterResume()
    }

    private var animation: Animation {
      .default
    }

    private var documentSourceIdentity: String {
      "native-pdf-\(book.id)"
    }

    private func documentViewIdentity(
      documentURL: URL,
      resolvedPresentation: PdfPagePresentation
    ) -> String {
      "\(documentURL.path)-\(documentSourceIdentity)-\(resolvedPresentation.rawValue)"
    }

    private var documentInitialPage: Int {
      if viewModel.pageCount > 0 {
        return max(1, min(viewModel.currentPageNumber, viewModel.pageCount))
      }
      return max(1, viewModel.initialPageNumber)
    }

    private var currentTOCSelection: ReaderTOCSelection {
      ReaderTOCSelection.resolve(
        in: viewModel.tableOfContents,
        currentPageIndex: max(0, viewModel.currentPageNumber - 1)
      )
    }

    @ViewBuilder
    private var contentView: some View {
      let showsDocument =
        viewModel.documentURL != nil && !viewModel.isLoading && viewModel.errorMessage == nil

      ZStack {
        if let documentURL = viewModel.documentURL {
          GeometryReader { proxy in
            let resolvedPresentation = pagePresentation.resolved(for: proxy.size)
            PdfDocumentView(
              documentURL: documentURL,
              pagePresentation: resolvedPresentation,
              isolateCoverPage: isolateCoverPage,
              readingDirection: readingDirection,
              initialPageNumber: documentInitialPage,
              targetPageNumber: targetPageNumber,
              navigationToken: navigationToken,
              onPageChange: { pageNumber, totalPages in
                viewModel.updateCurrentPage(pageNumber: pageNumber, totalPages: totalPages)
              },
              onSingleTap: { normalizedPoint in
                handleSingleTap(normalizedPoint: normalizedPoint)
              }
            )
            // Rebuild PDFView when the source document or resolved presentation changes.
            .id(documentViewIdentity(documentURL: documentURL, resolvedPresentation: resolvedPresentation))
            .readerIgnoresSafeArea()
          }
          .readerIgnoresSafeArea()
          .readerLoadingContent(isVisible: showsDocument)
        } else if !viewModel.isLoading && viewModel.errorMessage == nil {
          ReaderUnavailableView(
            icon: "doc.richtext",
            title: "PDF file unavailable",
            message: String(localized: "Offline PDF file is missing. Please try downloading again."),
            onClose: closeReader
          )
          .transition(ReaderLoadingTransition.content)
        }

        if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
          ReaderUnavailableView(
            icon: AppIcon.loadError,
            title: "Failed to load media",
            message: errorMessage,
            onRetry: {
              Task {
                await loadBook()
              }
            },
            onClose: closeReader
          )
          .transition(ReaderLoadingTransition.content)
        }

        if viewModel.isLoading {
          ReaderLoadingView(
            title: loadingTitle,
            detail: loadingDetail,
            progress: loadingProgress,
            cardFill: readerBackground.loadingCardFill,
            contentColor: readerBackground.loadingContentColor
          )
          .readerLoadingOverlay()
        }
      }
      .animation(ReaderLoadingTransition.animation, value: viewModel.isLoading)
      .animation(ReaderLoadingTransition.animation, value: viewModel.documentURL)
      .animation(ReaderLoadingTransition.animation, value: viewModel.errorMessage)
    }

    private var controlsOverlay: some View {
      PdfControlsOverlayView(
        readingDirection: $readingDirection,
        pagePresentation: $pagePresentation,
        isolateCoverPage: $isolateCoverPage,
        showingPageJumpSheet: $showingPageJumpSheet,
        showingSearchSheet: $showingSearchSheet,
        showingTOCSheet: $showingTOCSheet,
        showingReaderSettingsSheet: $showingPreferencesSheet,
        showingDetailSheet: $showingDetailSheet,
        currentBook: currentBook,
        fallbackTitle: readerTitle,
        incognito: incognito,
        currentPage: viewModel.currentPageNumber,
        pageCount: viewModel.pageCount,
        hasTOC: !viewModel.tableOfContents.isEmpty,
        canSearch: viewModel.documentURL != nil,
        controlsVisible: shouldShowControls,
        showGradientBackground: showControlsGradientBackground,
        showProgressBarWhileReading: showProgressBarWhileReading,
        onDismiss: closeReader
      )
    }

    private var loadingTitle: String {
      switch viewModel.loadingStage {
      case .fetchingMetadata:
        return String(localized: "Fetching book info...")
      case .downloading:
        return String(localized: "Downloading book...")
      case .finalizingOfflineDownload:
        return String(localized: "Finalizing offline PDF...")
      case .preparingReader:
        return String(localized: "Preparing PDF...")
      case .idle:
        return String(localized: "Loading book...")
      }
    }

    private var loadingProgress: Double? {
      switch viewModel.loadingStage {
      case .downloading:
        if let expectedBytes = viewModel.downloadBytesExpected, expectedBytes > 0 {
          return viewModel.downloadProgress
        }

        return viewModel.downloadProgress > 0 ? viewModel.downloadProgress : nil
      case .finalizingOfflineDownload, .preparingReader:
        return ReaderLoadingProgress.complete
      case .fetchingMetadata, .idle:
        return nil
      }
    }

    private var loadingDetail: String {
      switch viewModel.loadingStage {
      case .fetchingMetadata:
        return String(localized: "Checking PDF download information")
      case .finalizingOfflineDownload:
        return String(localized: "Saving downloaded PDF for offline reading")
      case .preparingReader:
        return String(localized: "Opening downloaded PDF file")
      case .downloading:
        break
      case .idle:
        return String(localized: "Opening downloaded PDF file")
      }

      guard viewModel.downloadBytesReceived > 0 else {
        return String(localized: "Downloading book content")
      }

      let formatter = ByteCountFormatter()
      formatter.countStyle = .file
      let received = formatter.string(fromByteCount: viewModel.downloadBytesReceived)

      if let expected = viewModel.downloadBytesExpected, expected > 0 {
        let total = formatter.string(fromByteCount: expected)
        return "\(received) / \(total)"
      }

      return received
    }

    private func loadBook() async {
      var resolvedBook: Book = book
      let database = await DatabaseOperator.databaseIfConfigured()

      if let cachedBook = await database?.fetchBook(id: book.id) {
        resolvedBook = cachedBook
      }

      if !isOffline {
        if let syncedBook = try? await SyncService.syncBook(bookId: book.id) {
          resolvedBook = syncedBook
        }
      }

      currentBook = resolvedBook
      if !incognito {
        readerPresentation.trackVisitedBook(
          sessionID: sessionID,
          bookId: resolvedBook.id,
          seriesId: resolvedBook.seriesId
        )
      }
      let resolvedSeries = await fetchSeries(for: resolvedBook)
      currentSeries = resolvedSeries
      readingDirection = resolvePreferredReadingDirection(series: resolvedSeries)
      await viewModel.load(book: resolvedBook)
      updateHandoff()
    }

    private func runSearch(query: String) {
      Task {
        await viewModel.search(text: query)
      }
    }

    private func toggleControls() {
      cancelAutoHideAfterResume()
      withAnimation(animation) {
        showingControls.toggle()
      }
    }

    private func handleSingleTap(normalizedPoint _: CGPoint) {
      toggleControls()
    }

    private func fetchSeries(for book: Book) async -> Series? {
      let database = await DatabaseOperator.databaseIfConfigured()
      var series = await database?.fetchSeries(id: book.seriesId)
      if series == nil && !isOffline {
        series = try? await SyncService.syncSeriesDetail(seriesId: book.seriesId)
      }
      return series
    }

    private func resolvePreferredReadingDirection(series: Series?) -> ReadingDirection {
      if forceDefaultReadingDirection {
        return pdfReadingDirection(from: defaultReadingDirection)
      }

      if let rawReadingDirection = series?.metadata.readingDirection?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawReadingDirection.isEmpty
      {
        return pdfReadingDirection(from: ReadingDirection.fromString(rawReadingDirection))
      }

      return pdfReadingDirection(from: defaultReadingDirection)
    }

    private func pdfReadingDirection(from direction: ReadingDirection) -> ReadingDirection {
      direction == .webtoon ? .vertical : direction
    }

    private func requestPageNavigation(to page: Int) {
      guard viewModel.pageCount > 0 else { return }
      let clamped = max(1, min(page, viewModel.pageCount))
      guard clamped != viewModel.currentPageNumber else { return }
      targetPageNumber = clamped
      navigationToken = UUID()
      showingControls = false
    }

    private func forcePageNavigation(to page: Int) {
      guard viewModel.pageCount > 0 else { return }
      let clamped = max(1, min(page, viewModel.pageCount))
      targetPageNumber = clamped
      navigationToken = UUID()
    }

    private func closeReader() {
      cancelAutoHideAfterResume()
      logger.debug(
        "🚪 Closing PDF reader for book \(book.id), page=\(viewModel.currentPageNumber)/\(viewModel.pageCount)"
      )
      if let onClose {
        onClose()
      } else {
        dismiss()
      }
    }

    private func updateHandoff() {
      let handoffBook = currentBook ?? book
      let url = KomgaWebLinkBuilder.bookReader(
        serverURL: current.serverURL,
        bookId: handoffBook.id,
        pageNumber: viewModel.pageCount > 0 ? viewModel.currentPageNumber : nil,
        incognito: incognito
      )
      readerPresentation.updateHandoff(
        sessionID: sessionID,
        title: handoffBook.metadata.title,
        url: url
      )
    }

    private var readerTitle: String {
      let title = (currentBook?.metadata.title ?? book.metadata.title)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return title
    }

    private var keyboardCommands: [ReaderKeyboardCommand] {
      var commands = [
        ReaderKeyboardCommand(
          title: "Keyboard Shortcuts",
          event: ReaderKeyboardEvent(key: .slash, modifiers: [.command])
        )
      ]

      if viewModel.documentURL != nil {
        commands.append(
          ReaderKeyboardCommand(
            title: "Search",
            event: ReaderKeyboardEvent(key: .f, modifiers: [.command])
          )
        )
      }

      if !viewModel.tableOfContents.isEmpty {
        commands.append(
          ReaderKeyboardCommand(
            title: "Table of Contents",
            event: ReaderKeyboardEvent(key: .t, modifiers: [.command])
          )
        )
      }

      if viewModel.pageCount > 0 {
        commands.append(
          ReaderKeyboardCommand(
            title: "Jump to Page",
            event: ReaderKeyboardEvent(key: .j, modifiers: [.command])
          )
        )
      }

      return commands
    }

    #if os(macOS)
      private var readerCommandState: ReaderCommandState {
        ReaderCommandState(
          isActive: true,
          supportsReaderSettings: true,
          supportsBookDetails: currentBook != nil && currentSeries != nil,
          hasPages: viewModel.pageCount > 0,
          hasTableOfContents: !viewModel.tableOfContents.isEmpty,
          supportsPageJump: true,
          supportsBookNavigation: false,
          canOpenPreviousBook: false,
          canOpenNextBook: false,
          readingDirection: readingDirection,
          availableReadingDirections: ReadingDirection.pdfAvailableCases,
          pageLayout: pagePresentation.resolvedPageLayout,
          isolateCoverPage: isolateCoverPage,
          pageIsolationActions: [],
          splitWidePageMode: .none,
          continuousScroll: pagePresentation.resolvedContinuousScroll,
          supportsSearch: true,
          canSearch: viewModel.documentURL != nil,
          supportsReadingDirectionSelection: true,
          supportsPageLayoutSelection: false,
          supportsDualPageOptions: pagePresentation.supportsCoverIsolation,
          supportsSplitWidePageMode: false,
          supportsContinuousScrollToggle: false
        )
      }
    #endif

    private var keyboardHelpOverlay: some View {
      KeyboardHelpOverlay(
        readingDirection: readingDirection,
        hasTOC: !viewModel.tableOfContents.isEmpty,
        supportsFullscreenToggle: supportsFullscreenToggle,
        supportsLiveText: false,
        supportsJumpToPage: viewModel.pageCount > 0,
        supportsSearch: viewModel.documentURL != nil,
        supportsToggleControls: true,
        hasNextBook: false,
        onDismiss: {
          hideKeyboardHelp()
        }
      )
      .opacity(showKeyboardHelp ? 1.0 : 0.0)
      .allowsHitTesting(showKeyboardHelp)
      .animation(.appCurve(), value: showKeyboardHelp)
    }

    #if os(macOS)
      private func configureReaderCommands() {
        readerPresentation.configureReaderCommands(
          state: readerCommandState,
          handlers: ReaderCommandHandlers(
            showReaderSettings: {
              showingPreferencesSheet = true
            },
            showBookDetails: {
              if currentBook != nil && currentSeries != nil {
                showingDetailSheet = true
              }
            },
            showTableOfContents: {
              if !viewModel.tableOfContents.isEmpty {
                showingTOCSheet = true
              }
            },
            showPageJump: {
              if viewModel.pageCount > 0 {
                showingPageJumpSheet = true
              }
            },
            showSearch: {
              if viewModel.documentURL != nil {
                showingSearchSheet = true
              }
            },
            openPreviousBook: {},
            openNextBook: {},
            setReadingDirection: { direction in
              readingDirection = pdfReadingDirection(from: direction)
            },
            setPageLayout: { _ in },
            toggleIsolateCoverPage: {
              isolateCoverPage.toggle()
            },
            toggleIsolatePage: { _ in },
            sharePage: { _ in },
            setRotation: { _ in },
            setSplitWidePageMode: { _ in },
            toggleContinuousScroll: {}
          )
        )
      }
    #endif

    private func handleKeyboardEvent(_ event: ReaderKeyboardEvent) -> Bool {
      guard !isPresentingModalSheet else { return false }

      if event.matches(.escape) {
        closeReader()
        return true
      }

      if event.matches(.slash, modifiers: [.shift])
        || event.matches(.slash, modifiers: [.command])
        || event.matches(.h)
      {
        toggleKeyboardHelpManually()
        return true
      }

      if event.matches(.returnOrEnter) {
        return toggleFullscreenIfSupported()
      }

      if event.matches(.space) {
        toggleControls()
        return true
      }

      if event.matches(.f, modifiers: [.command]) {
        guard viewModel.documentURL != nil else { return false }
        showingSearchSheet = true
        return true
      }

      if event.matches(.t, modifiers: [.command]) {
        guard !viewModel.tableOfContents.isEmpty else { return false }
        showingTOCSheet = true
        return true
      }

      if event.matches(.j, modifiers: [.command]) {
        guard viewModel.pageCount > 0 else { return false }
        showingPageJumpSheet = true
        return true
      }

      guard !event.hasSystemModifiers else { return false }

      if event.matches(.f) {
        guard viewModel.documentURL != nil else { return false }
        showingSearchSheet = true
        return true
      }

      if event.matches(.c) {
        toggleControls()
        return true
      }

      if event.matches(.t) {
        guard !viewModel.tableOfContents.isEmpty else { return false }
        showingTOCSheet = true
        return true
      }

      if event.matches(.j) {
        guard viewModel.pageCount > 0 else { return false }
        showingPageJumpSheet = true
        return true
      }

      guard viewModel.pageCount > 0 else { return false }

      switch readingDirection {
      case .ltr:
        switch event.key {
        case .rightArrow:
          goToNextPage()
          return true
        case .leftArrow:
          goToPreviousPage()
          return true
        default:
          return false
        }
      case .rtl:
        switch event.key {
        case .leftArrow:
          goToNextPage()
          return true
        case .rightArrow:
          goToPreviousPage()
          return true
        default:
          return false
        }
      case .vertical, .webtoon:
        switch event.key {
        case .downArrow:
          goToNextPage()
          return true
        case .upArrow:
          goToPreviousPage()
          return true
        default:
          return false
        }
      }
    }

    private func goToNextPage() {
      requestPageNavigation(to: viewModel.currentPageNumber + 1)
    }

    private func goToPreviousPage() {
      requestPageNavigation(to: viewModel.currentPageNumber - 1)
    }

    private func toggleFullscreenIfSupported() -> Bool {
      #if os(macOS)
        if let window = NSApplication.shared.keyWindow {
          window.toggleFullScreen(nil)
          return true
        }
      #endif
      return false
    }

    private var supportsFullscreenToggle: Bool {
      #if os(macOS)
        true
      #else
        false
      #endif
    }

    private func hideKeyboardHelp() {
      keyboardHelpTimer?.invalidate()
      keyboardHelpTimer = nil
      showKeyboardHelp = false
    }

    private func toggleKeyboardHelpManually() {
      keyboardHelpTimer?.invalidate()
      keyboardHelpTimer = nil
      showKeyboardHelp.toggle()
    }

    private func triggerKeyboardHelp(timeout: TimeInterval) {
      keyboardHelpTimer?.invalidate()
      guard showKeyboardHelpOverlay, viewModel.pageCount > 0 else { return }
      guard ReaderKeyboardAvailability.shouldAutoShowKeyboardHelp else { return }

      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        self.showKeyboardHelp = true
        self.keyboardHelpTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
          Task { @MainActor in
            self.hideKeyboardHelp()
          }
        }
      }
    }
  }
#endif
