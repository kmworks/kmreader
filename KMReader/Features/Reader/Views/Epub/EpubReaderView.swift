//
// EpubReaderView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct EpubReaderView: View {
    private let sessionID: UUID
    private let book: Book
    private let incognito: Bool
    private let readListContext: ReaderReadListContext?
    private let readerPresentation: ReaderPresentationManager
    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("currentAccount") private var current: Current = .init()
    @AppStorage("epubPreferences") private var globalThemePreferences: EpubThemePreferences = .init()
    @AppStorage("epubFlowStyle") private var epubFlowStyle: EpubFlowStyle = .paged
    @AppStorage("epubTapScrollPercentage") private var epubTapScrollPercentage: Double = AppConfig
      .epubTapScrollPercentage
    @AppStorage("epubPageTransitionStyle") private var epubPageTransitionStyle: PageTransitionStyle = .scroll
    @AppStorage("epubShowsStatusBarWhileReading") private var epubShowsStatusBarWhileReading: Bool = false
    @AppStorage("animateEpubTapTurns") private var animateEpubTapTurns: Bool = AppConfig.animateEpubTapTurns
    @AppStorage("epubOverlayPreferences") private var epubOverlayPreferences: EpubOverlayPreferences = AppConfig
      .epubOverlayPreferences
    @AppStorage("epubShowKeyboardHelpOverlay")
    private var showKeyboardHelpOverlay: Bool = AppConfig.epubShowKeyboardHelpOverlay

    @State private var viewModel: EpubReaderViewModel
    @State private var activeThemePreferences: EpubThemePreferences
    @State private var bookThemePreferences: EpubThemePreferences?
    @State private var showingControls = false
    // Captures `shouldShowControls` on the active → non-active scene-phase
    // transition (before the force-show below flips `showingControls`), so
    // the subsequent resume can decide whether to auto-hide the overlay or
    // leave it visible. See `handleScenePhaseChange(from:to:)`.
    @State private var wasShowingControlsBeforeBackground: Bool = false
    // Task that fades the resume-triggered overlay back to hidden after a
    // brief glance window. Reset on user interaction (location change) to act
    // as an idle timeout; cancelled on tap-toggle and reader close.
    @State private var autoHideAfterResumeTask: Task<Void, Never>?
    @State private var currentSeries: Series?
    @State private var currentBook: Book?
    @State private var showingChapterSheet = false
    @State private var showingThemeSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingDetailSheet = false
    @State private var showingQuickActions = false
    @State private var showingEndPage = false
    @State private var keyboardHelpTimer: Timer?
    @State private var showKeyboardHelp = false

    private let logger = AppLogger(.reader)

    init(
      sessionID: UUID,
      book: Book,
      incognito: Bool = false,
      readListContext: ReaderReadListContext? = nil,
      readerPresentation: ReaderPresentationManager,
      onClose: (() -> Void)? = nil
    ) {
      self.sessionID = sessionID
      self.book = book
      self.incognito = incognito
      self.readListContext = readListContext
      self.readerPresentation = readerPresentation
      self.onClose = onClose
      _viewModel = State(initialValue: EpubReaderViewModel(incognito: incognito))
      _activeThemePreferences = State(initialValue: AppConfig.epubThemePreferences)
      _bookThemePreferences = State(initialValue: nil)
      _currentBook = State(initialValue: book)
    }

    private func closeReader() {
      cancelAutoHideAfterResume()
      logger.debug(
        "🚪 Closing EPUB reader for book \(handoffBookId), chapter=\(viewModel.currentChapterIndex), page=\(viewModel.currentPageIndex)"
      )
      if let onClose {
        onClose()
      } else {
        dismiss()
      }
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
    /// existing user-interaction observers (e.g., location changes) so the
    /// auto-hide acts as an idle timeout: interaction within the window
    /// resets the clock, and the overlay only fades when the user actually
    /// pauses.
    private func resetAutoHideAfterResumeIfPending() {
      guard autoHideAfterResumeTask != nil else { return }
      scheduleAutoHideAfterResume()
    }

    var shouldShowControls: Bool {
      guard viewModel.errorMessage == nil else { return true }
      guard !viewModel.isLoading else { return true }
      return showingControls
    }

    private var shouldShowStatusBar: Bool {
      shouldShowControls || epubShowsStatusBarWhileReading
    }

    private var isPresentingModalSheet: Bool {
      showingChapterSheet
        || showingThemeSheet
        || showingSettingsSheet
        || showingDetailSheet
    }

    private var isKeyboardCaptureEnabled: Bool {
      !isPresentingModalSheet
    }

    private var handoffBookId: String {
      currentBook?.id ?? book.id
    }

    private var handoffTitle: String {
      currentBook?.metadata.title ?? book.metadata.title
    }

    private var animation: Animation {
      .default
    }

    private var isUsingBookPreferences: Bool {
      bookThemePreferences != nil
    }

    private var dismissGestureReadingDirection: ReadingDirection {
      switch epubFlowStyle {
      case .paged:
        return viewModel.publicationReadingProgression == .rtl ? .rtl : .ltr
      case .scrolled:
        return .webtoon
      }
    }

    private var readerTheme: ReaderTheme {
      activeThemePreferences.resolvedTheme(fallbackColorScheme: colorScheme)
    }

    private var readerColorScheme: ColorScheme {
      activeThemePreferences.resolvedColorScheme(fallbackColorScheme: colorScheme)
    }

    private var loadingCardFill: Color {
      switch readerTheme {
      case .white:
        return Color(.sRGB, white: 0.96, opacity: 1)
      case .black:
        return Color(.sRGB, white: 0.12, opacity: 1)
      case .lightQuiet:
        return Color(hex: "#F0F0F0") ?? readerTheme.backgroundColor
      case .darkQuiet:
        return Color(hex: "#2A2A2A") ?? readerTheme.backgroundColor
      case .lightSepia:
        return Color(hex: "#FAF4E4") ?? readerTheme.backgroundColor
      case .darkSepia:
        return Color(hex: "#44382D") ?? readerTheme.backgroundColor
      case .lightGreen:
        return Color(hex: "#D8F5DC") ?? readerTheme.backgroundColor
      case .darkGreen:
        return Color(hex: "#243324") ?? readerTheme.backgroundColor
      }
    }

    private var loadingContentColor: Color {
      readerTheme.textColor
    }

    #if os(macOS)
      private var supportsOverlayControls: Bool {
        false
      }

      private var supportsKeyboardOverlayToggle: Bool {
        true
      }
    #else
      private var supportsOverlayControls: Bool {
        true
      }

      private var supportsKeyboardOverlayToggle: Bool {
        supportsOverlayControls
      }
    #endif

    private func updateHandoff() {
      let url = KomgaWebLinkBuilder.epubReader(
        serverURL: current.serverURL,
        bookId: handoffBookId,
        incognito: incognito
      )
      readerPresentation.updateHandoff(sessionID: sessionID, title: handoffTitle, url: url)
    }

    private func updateReaderLiveActivityProgress() {
      #if os(iOS)
        let progress = viewModel.currentLocation?.totalProgression ?? 0
        ReaderLiveActivityManager.shared.updateReadingProgress(progress)
      #endif
    }

    var body: some View {
      readerBody
        #if os(iOS)
          .statusBarHidden(!shouldShowStatusBar)
          .iPadIgnoresSafeArea()
        #endif
        .task(id: book.id) {
          readerPresentation.registerFlushHandler(for: sessionID) {
            viewModel.flushProgress()
          }
          await loadBook()
        }
        .onAppear {
          updateHandoff()
          viewModel.applyPreferences(activeThemePreferences, colorScheme: readerColorScheme)
          #if os(macOS)
            configureReaderCommands()
          #endif
        }
        .onChange(of: currentBook) { _, newBook in
          if let newBook {
            readerPresentation.updatePresentedBook(sessionID: sessionID, book: newBook)
          }
          updateHandoff()
        }
        #if os(macOS)
          .onChange(of: readerCommandState) { _, newState in
            readerPresentation.updateReaderCommandState(newState)
          }
        #endif
        .onChange(of: viewModel.currentLocation) { _, _ in
          updateReaderLiveActivityProgress()
          // Treat location changes as user activity: if we're inside the post-
          // resume auto-hide window, restart the timer so the overlay stays
          // visible while the user is actively navigating and only fades after
          // a real pause.
          resetAutoHideAfterResumeIfPending()
        }
        .onChange(of: viewModel.hasContent) { oldValue, newValue in
          if !oldValue && newValue {
            triggerKeyboardHelp(timeout: 1.5)
          }
        }
        .onChange(of: showingEndPage) { _, newValue in
          guard newValue else { return }
          #if os(iOS)
            ReaderLiveActivityManager.shared.updateReadingProgress(1)
          #endif
        }
        .onChange(of: activeThemePreferences) { _, newPrefs in
          viewModel.applyPreferences(
            newPrefs,
            colorScheme: newPrefs.resolvedColorScheme(fallbackColorScheme: colorScheme)
          )
        }
        .onChange(of: globalThemePreferences) { _, newPrefs in
          guard !isUsingBookPreferences else { return }
          activeThemePreferences = newPrefs
        }
        .onChange(of: colorScheme) { _, newScheme in
          let newReaderColorScheme = activeThemePreferences.resolvedColorScheme(
            fallbackColorScheme: newScheme
          )
          viewModel.applyPreferences(activeThemePreferences, colorScheme: newReaderColorScheme)
        }
        .onReceive(
          NotificationCenter.default.publisher(for: .fileDownloadProgress)
        ) { notification in
          viewModel.updateDownloadProgress(notification: notification)
        }
        .onDisappear {
          logger.debug(
            "👋 EPUB reader disappeared for book \(handoffBookId), chapter=\(viewModel.currentChapterIndex), page=\(viewModel.currentPageIndex), hasLocation=\(viewModel.currentLocation != nil)"
          )
          #if os(macOS)
            keyboardHelpTimer?.invalidate()
          #endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
          handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        #if os(iOS)
          .readerDismissGesture(readingDirection: dismissGestureReadingDirection)
        #endif
        .background(
          KeyboardEventHandler(
            isEnabled: isKeyboardCaptureEnabled,
            commands: keyboardCommands,
            onKeyPress: handleKeyboardEvent
          )
        )
    }

    private func loadBook() async {
      viewModel.beginLoading()

      currentBook = book
      bookThemePreferences = nil
      activeThemePreferences = globalThemePreferences
      do {
        currentBook = try await SyncService.syncBook(bookId: book.id)
      } catch {
      }

      guard let activeBook = currentBook else {
        viewModel.errorMessage =
          AppErrorType.missingRequiredData(
            message: "Missing book metadata. Please try again."
          ).localizedDescription
        viewModel.loadingStage = .idle
        viewModel.isLoading = false
        return
      }

      let database = await DatabaseOperator.databaseIfConfigured()
      let savedThemePreferences = await database?.fetchBookEpubThemePreferences(bookId: activeBook.id)
      if !incognito {
        readerPresentation.trackVisitedBook(
          sessionID: sessionID,
          bookId: activeBook.id,
          seriesId: activeBook.seriesId
        )
      }
      bookThemePreferences = savedThemePreferences
      activeThemePreferences = savedThemePreferences ?? globalThemePreferences

      // Refresh WebPub manifest if online
      if !AppConfig.isOffline {
        do {
          let manifest = try await BookService.getBookWebPubManifest(bookId: activeBook.id)
          await database?.updateBookWebPubManifest(bookId: activeBook.id, manifest: manifest)
        } catch {
          // Silently fail - we'll use cached manifest
        }
      }

      var series = await database?.fetchSeries(id: activeBook.seriesId)
      if series == nil && !AppConfig.isOffline {
        do {
          series = try await SyncService.syncSeriesDetail(seriesId: activeBook.seriesId)
        } catch {
          // Silently fail
        }
      }
      if let series = series {
        currentSeries = series
      }

      await viewModel.load(book: activeBook)
    }

    @ViewBuilder
    private var readerBody: some View {
      GeometryReader { geometry in
        ZStack {
          readerTheme.backgroundColor.readerIgnoresSafeArea()

          contentView(for: geometry.size, viewModel: viewModel)

          controlsOverlay

          keyboardHelpOverlay
        }
        .onAppear {
          viewModel.updateViewport(size: geometry.size)
        }
        .onChange(of: geometry.size) { _, newSize in
          viewModel.updateViewport(size: newSize)
        }
      }
    }

    @ViewBuilder
    private func contentView(for size: CGSize, viewModel: EpubReaderViewModel) -> some View {
      Group {
        if showingEndPage {
          EpubEndPageView(
            bookTitle: currentBook?.metadata.title,
            preferences: activeThemePreferences,
            colorScheme: readerColorScheme,
            onReturn: {
              // Hide end page first, then navigate to last page
              showingEndPage = false

              // Navigate back to the last page of the last chapter
              Task { @MainActor in
                // Small delay to ensure view hierarchy is updated
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                if let lastPosition = viewModel.lastPagePosition() {
                  viewModel.targetChapterIndex = lastPosition.chapterIndex
                  viewModel.targetPageIndex = lastPosition.pageIndex
                }
              }
            },
            onClose: {
              closeReader()
            }
          )
        } else {
          let showsReaderContent =
            viewModel.hasContent && !viewModel.isLoading && viewModel.errorMessage == nil

          ZStack {
            #if os(iOS)
              readerContent
                .readerLoadingContent(isVisible: showsReaderContent)
            #else
              if showsReaderContent {
                readerContent
                  .transition(ReaderLoadingTransition.content)
              }
            #endif

            if let error = viewModel.errorMessage, !viewModel.isLoading {
              ReaderUnavailableView(
                icon: AppIcon.loadError,
                title: "Failed to load media",
                message: error,
                onRetry: {
                  Task {
                    await loadBook()
                  }
                },
                onClose: closeReader
              )
              .transition(ReaderLoadingTransition.content)
            } else if !viewModel.isLoading && !viewModel.hasContent {
              ReaderUnavailableView(
                icon: "doc.questionmark",
                title: "No content available.",
                onClose: closeReader
              )
              .transition(ReaderLoadingTransition.content)
            }

            if viewModel.isLoading {
              ReaderLoadingView(
                title: loadingTitle,
                detail: loadingDetail,
                progress: loadingProgress,
                cardFill: loadingCardFill,
                contentColor: loadingContentColor
              )
              .readerLoadingOverlay()
            }
          }
          .animation(ReaderLoadingTransition.animation, value: viewModel.isLoading)
          .animation(ReaderLoadingTransition.animation, value: viewModel.errorMessage)
          .animation(ReaderLoadingTransition.animation, value: viewModel.hasContent)
        }
      }
    }

    @ViewBuilder
    private var readerContent: some View {
      #if os(macOS)
        switch epubFlowStyle {
        case .paged:
          switch epubPageTransitionStyle {
          case .cover:
            WebPubPagedCoverView(
              viewModel: viewModel,
              preferences: activeThemePreferences,
              colorScheme: readerColorScheme,
              animateTapTurns: animateEpubTapTurns,
              overlayPreferences: epubOverlayPreferences,
              showingControls: shouldShowControls,
              bookTitle: currentBook?.metadata.title,
              onCenterTap: {
                toggleControls()
              },
              onEndReached: {
                if !showingEndPage {
                  viewModel.syncEndProgression()
                  showingEndPage = true
                }
              }
            )
          case .scroll, .pageCurl:
            WebPubPagedScrollView(
              viewModel: viewModel,
              animatePageTransitions: animateEpubTapTurns,
              preferences: activeThemePreferences,
              colorScheme: readerColorScheme,
              overlayPreferences: epubOverlayPreferences,
              showingControls: shouldShowControls,
              bookTitle: currentBook?.metadata.title,
              onCenterTap: {
                toggleControls()
              },
              onEndReached: {
                if !showingEndPage {
                  viewModel.syncEndProgression()
                  showingEndPage = true
                }
              }
            )
          }
        case .scrolled:
          WebPubScrolledView(
            viewModel: viewModel,
            preferences: activeThemePreferences,
            colorScheme: readerColorScheme,
            tapScrollPercentage: epubTapScrollPercentage,
            animateTapTurns: animateEpubTapTurns,
            overlayPreferences: epubOverlayPreferences,
            showingControls: shouldShowControls,
            bookTitle: currentBook?.metadata.title,
            onCenterTap: {
              toggleControls()
            },
            onEndReached: {
              if !showingEndPage {
                viewModel.syncEndProgression()
                showingEndPage = true
              }
            }
          )
        }
      #else
        switch epubFlowStyle {
        case .paged:
          switch epubPageTransitionStyle {
          case .scroll:
            WebPubPagedScrollView(
              viewModel: viewModel,
              animatePageTransitions: animateEpubTapTurns,
              preferences: activeThemePreferences,
              colorScheme: readerColorScheme,
              overlayPreferences: epubOverlayPreferences,
              showingControls: shouldShowControls,
              bookTitle: currentBook?.metadata.title,
              onCenterTap: {
                toggleControls()
              },
              onEndReached: {
                if !showingEndPage {
                  viewModel.syncEndProgression()
                  showingEndPage = true
                }
              }
            ).readerIgnoresSafeArea()
          case .cover:
            WebPubPagedCoverView(
              viewModel: viewModel,
              preferences: activeThemePreferences,
              colorScheme: readerColorScheme,
              animateTapTurns: animateEpubTapTurns,
              overlayPreferences: epubOverlayPreferences,
              showingControls: shouldShowControls,
              bookTitle: currentBook?.metadata.title,
              onCenterTap: {
                toggleControls()
              },
              onEndReached: {
                if !showingEndPage {
                  viewModel.syncEndProgression()
                  showingEndPage = true
                }
              }
            ).readerIgnoresSafeArea()
          case .pageCurl:
            WebPubPagedCurlView(
              viewModel: viewModel,
              preferences: activeThemePreferences,
              colorScheme: readerColorScheme,
              animateTapTurns: animateEpubTapTurns,
              overlayPreferences: epubOverlayPreferences,
              showingControls: shouldShowControls,
              bookTitle: currentBook?.metadata.title,
              onCenterTap: {
                toggleControls()
              },
              onEndReached: {
                if !showingEndPage {
                  viewModel.syncEndProgression()
                  showingEndPage = true
                }
              }
            ).readerIgnoresSafeArea()
          }
        case .scrolled:
          WebPubScrolledView(
            viewModel: viewModel,
            preferences: activeThemePreferences,
            colorScheme: readerColorScheme,
            tapScrollPercentage: epubTapScrollPercentage,
            animateTapTurns: animateEpubTapTurns,
            overlayPreferences: epubOverlayPreferences,
            showingControls: shouldShowControls,
            bookTitle: currentBook?.metadata.title,
            onCenterTap: {
              toggleControls()
            },
            onEndReached: {
              if !showingEndPage {
                viewModel.syncEndProgression()
                showingEndPage = true
              }
            }
          ).readerIgnoresSafeArea()
        }
      #endif
    }

    private var loadingTitle: String {
      switch viewModel.loadingStage {
      case .fetchingMetadata:
        return String(localized: "Fetching book info...")
      case .downloading:
        return String(localized: "Downloading book...")
      case .finalizingOfflineDownload:
        return String(localized: "Finalizing offline EPUB...")
      case .preparingOfflineResources:
        return String(localized: "Preparing offline EPUB...")
      case .preparingReader:
        return String(localized: "Preparing reader...")
      case .paginating:
        return String(localized: "Paginating chapters...")
      case .idle:
        return String(localized: "Loading...")
      }
    }

    private var loadingProgress: Double? {
      switch viewModel.loadingStage {
      case .downloading:
        if let expectedBytes = viewModel.downloadBytesExpected, expectedBytes > 0 {
          return viewModel.downloadProgress
        }

        return viewModel.downloadProgress > 0 ? viewModel.downloadProgress : nil
      case .finalizingOfflineDownload, .preparingOfflineResources, .preparingReader, .paginating:
        return ReaderLoadingProgress.complete
      case .fetchingMetadata, .idle:
        return nil
      }
    }

    private var loadingDetail: String {
      switch viewModel.loadingStage {
      case .fetchingMetadata:
        return String(localized: "Fetching book metadata")
      case .downloading:
        guard viewModel.downloadBytesReceived > 0 else {
          return String(localized: "Downloading book content")
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let received = formatter.string(fromByteCount: viewModel.downloadBytesReceived)
        if let expectedBytes = viewModel.downloadBytesExpected, expectedBytes > 0 {
          let total = formatter.string(fromByteCount: expectedBytes)
          return "\(received) / \(total)"
        }
        return received
      case .finalizingOfflineDownload:
        return String(localized: "Saving downloaded EPUB for offline reading")
      case .preparingOfflineResources:
        return String(localized: "Extracting reader resources from downloaded EPUB")
      case .preparingReader:
        return String(localized: "Preparing reader view")
      case .paginating:
        return String(localized: "Calculating chapter pages")
      case .idle:
        return String(localized: "Loading...")
      }
    }

    @ViewBuilder
    private var controlsOverlay: some View {
      Color.clear
        .overlay(alignment: .topTrailing) {
          if supportsOverlayControls && shouldShowControls {
            Button {
              closeReader()
            } label: {
              Image(systemName: AppIcon.close)
                .contentShape(Circle())
            }
            .controlSize(.extraLarge)
            .buttonBorderShape(.circle)
            .readerControlButtonStyle()
            .padding(.top, 24)
            .padding(.trailing, 12)
            .transition(.scale(scale: 0).combined(with: .opacity))
          }
        }
        .overlay(alignment: .bottomTrailing) {
          VStack(alignment: .trailing) {
            if supportsOverlayControls && shouldShowControls && showingQuickActions {
              quickActionsPanel
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if supportsOverlayControls && shouldShowControls {
              Button {
                withAnimation(animation) {
                  showingQuickActions.toggle()
                }
              } label: {
                Image(systemName: showingQuickActions ? AppIcon.close : "line.3.horizontal")
                  .padding(2)
                  .contentTransition(.symbolEffect(.replace, options: .nonRepeating))
                  .contentShape(Circle())
              }
              .controlSize(.extraLarge)
              .buttonBorderShape(.circle)
              .readerControlButtonStyle()
              .padding(.bottom, 24)
              .padding(.trailing, 12)
              .transition(.scale(scale: 0).combined(with: .opacity))
            }
          }
        }
        .iPadIgnoresSafeArea(paddingTop: 24)
        .allowsHitTesting(supportsOverlayControls && shouldShowControls)
        .sheet(isPresented: $showingChapterSheet) {
          EpubTocSheetView(
            chapters: viewModel.tableOfContents,
            currentLink: currentChapterLink,
            goToChapter: { link in
              showingChapterSheet = false
              viewModel.goToChapter(link: link)
            }
          )
        }
        .sheet(isPresented: $showingThemeSheet) {
          NavigationStack {
            EpubThemePreferencesView(
              inSheet: true,
              bookId: currentBook?.id ?? book.id,
              hasBookThemePreferences: bookThemePreferences != nil,
              initialThemePreferences: activeThemePreferences,
              onThemePreferencesSaved: { newPreferences in
                activeThemePreferences = newPreferences
                bookThemePreferences = newPreferences
              },
              onThemePreferencesCleared: {
                activeThemePreferences = globalThemePreferences
                bookThemePreferences = nil
              }
            )
          }
        }
        .sheet(isPresented: $showingSettingsSheet) {
          EpubReaderSettingsView(inSheet: true)
        }
        .readerDetailSheet(
          isPresented: $showingDetailSheet,
          book: currentBook,
          series: currentSeries
        )
    }

    @ViewBuilder
    private var quickActionsPanel: some View {
      VStack(alignment: .trailing, spacing: 6) {
        if let currentLocation = viewModel.currentLocation,
          let totalProgression = currentLocation.totalProgression
        {
          Button {
            showingChapterSheet = true
          } label: {
            HStack {
              Text("Contents · \(totalProgression, format: .percent.precision(.fractionLength(1)))")
                .font(.callout)
              Image(systemName: "list.bullet")
            }
            .contentShape(Capsule())
          }
          .readerControlButtonStyle()
          .buttonBorderShape(.capsule)
          .controlSize(.large)
          .disabled(viewModel.tableOfContents.isEmpty)
        }

        Button {
          showingDetailSheet = true
        } label: {
          HStack {
            Text("Book Info")
              .font(.callout)
            Image(systemName: AppIcon.details)
          }
          .contentShape(Capsule())
        }
        .readerControlButtonStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.large)

        Button {
          showingSettingsSheet = true
        } label: {
          HStack {
            Text("Settings")
              .font(.callout)
            Image(systemName: AppIcon.settings)
          }
          .contentShape(Capsule())
        }
        .readerControlButtonStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.large)

        Button {
          showingThemeSheet = true
        } label: {
          HStack {
            Text("Theme")
              .font(.callout)
            Image(systemName: "textformat")
          }
          .contentShape(Capsule())
        }
        .readerControlButtonStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.large)
      }
      .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func toggleControls() {
      cancelAutoHideAfterResume()
      let shouldHideControls = showingControls
      withAnimation(animation) {
        showingControls.toggle()
        if shouldHideControls {
          showingQuickActions = false
        }
      }
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

    private var currentChapterLink: WebPubLink? {
      guard let currentLocation = viewModel.currentLocation else {
        return nil
      }
      return findLink(href: currentLocation.href, in: viewModel.tableOfContents)
    }

    private func findLink(href: String, in links: [WebPubLink]) -> WebPubLink? {
      for link in links {
        if link.href == href {
          return link
        }
        if let children = link.children, let found = findLink(href: href, in: children) {
          return found
        }
      }
      return nil
    }

    private var isAtLastEpubPage: Bool {
      guard let lastPosition = viewModel.lastPagePosition() else { return false }
      return viewModel.currentChapterIndex == lastPosition.chapterIndex
        && viewModel.currentPageIndex >= lastPosition.pageIndex
    }

    private func goToNextEpubPage() {
      if isAtLastEpubPage {
        if !showingEndPage {
          viewModel.syncEndProgression()
          showingEndPage = true
        }
        return
      }
      viewModel.goToNextPage()
    }

    private var keyboardCommands: [ReaderKeyboardCommand] {
      var commands = [
        ReaderKeyboardCommand(
          title: "Keyboard Shortcuts",
          event: ReaderKeyboardEvent(key: .slash, modifiers: [.command])
        )
      ]

      if !viewModel.tableOfContents.isEmpty {
        commands.append(
          ReaderKeyboardCommand(
            title: "Table of Contents",
            event: ReaderKeyboardEvent(key: .t, modifiers: [.command])
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
          hasPages: viewModel.hasContent,
          hasTableOfContents: !viewModel.tableOfContents.isEmpty,
          supportsPageJump: false,
          supportsBookNavigation: false,
          canOpenPreviousBook: false,
          canOpenNextBook: false,
          readingDirection: dismissGestureReadingDirection,
          availableReadingDirections: [],
          pageLayout: .single,
          soloCoverPage: false,
          pageSoloActions: [],
          splitWidePageMode: .none,
          supportsSearch: false,
          canSearch: false,
          supportsReadingDirectionSelection: false,
          supportsPageLayoutSelection: false,
          supportsDualPageOptions: false,
          supportsSplitWidePageMode: false
        )
      }
    #endif

    private var keyboardHelpOverlay: some View {
      KeyboardHelpOverlay(
        readingDirection: dismissGestureReadingDirection,
        hasTOC: !viewModel.tableOfContents.isEmpty,
        supportsFullscreenToggle: supportsFullscreenToggle,
        supportsLiveText: false,
        supportsJumpToPage: false,
        supportsToggleControls: supportsKeyboardOverlayToggle,
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
              showingSettingsSheet = true
            },
            showBookDetails: {
              if currentBook != nil && currentSeries != nil {
                showingDetailSheet = true
              }
            },
            showTableOfContents: {
              if !viewModel.tableOfContents.isEmpty {
                showingChapterSheet = true
              }
            },
            showPageJump: {},
            showSearch: {},
            openPreviousBook: {},
            openNextBook: {},
            setReadingDirection: { _ in },
            setPageLayout: { _ in },
            toggleSoloCoverPage: {},
            toggleSoloPage: { _ in },
            sharePage: { _ in },
            setRotation: { _ in },
            setSplitWidePageMode: { _ in },
            toggleContinuousScroll: {}
          )
        )
      }
    #endif

    private func handleKeyboardEvent(_ event: ReaderKeyboardEvent) -> Bool {
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

      if event.matches(.t, modifiers: [.command]) {
        if !viewModel.tableOfContents.isEmpty {
          showingChapterSheet = true
        }
        return true
      }

      guard !event.hasSystemModifiers else { return false }

      if event.matches(.c) {
        toggleControls()
        return true
      }

      if event.matches(.t) {
        if !viewModel.tableOfContents.isEmpty {
          showingChapterSheet = true
        }
        return true
      }

      guard viewModel.hasContent else { return false }

      switch dismissGestureReadingDirection {
      case .ltr:
        switch event.key {
        case .rightArrow:
          goToNextEpubPage()
          return true
        case .leftArrow:
          viewModel.goToPreviousPage()
          return true
        default:
          return false
        }
      case .rtl:
        switch event.key {
        case .leftArrow:
          goToNextEpubPage()
          return true
        case .rightArrow:
          viewModel.goToPreviousPage()
          return true
        default:
          return false
        }
      case .vertical, .webtoon:
        switch event.key {
        case .downArrow:
          goToNextEpubPage()
          return true
        case .upArrow:
          viewModel.goToPreviousPage()
          return true
        default:
          return false
        }
      }
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
      guard showKeyboardHelpOverlay, viewModel.hasContent else { return }
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
