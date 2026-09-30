//
// DivinaReaderView.swift
//
//

import SwiftUI

struct DivinaReaderView: View {
  private enum ReaderNavigationStep {
    case previous
    case next
  }

  let sessionID: UUID
  let book: Book
  let incognito: Bool
  let readListContext: ReaderReadListContext?
  let readerPresentation: ReaderPresentationManager
  let onClose: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("readerBackground") private var readerBackground: ReaderBackground = .system
  @AppStorage("webtoonPageWidthPercentage") private var webtoonPageWidthPercentage: Double = 100.0
  @AppStorage("pageTransitionStyle") private var pageTransitionStyle: PageTransitionStyle = .cover
  @AppStorage("animateTapTurns") private var animateTapTurns: Bool = AppConfig.animateTapTurns
  @AppStorage("showTapZoneHints") private var showTapZoneHints: Bool = true
  @AppStorage("tapZoneMode") private var tapZoneMode: TapZoneMode = .defaultLayout
  @AppStorage("tapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = .auto
  @AppStorage("showPageNumber") private var showPageNumber: Bool = true
  @AppStorage("showPageShadow") private var showPageShadow: Bool = AppConfig.showPageShadow
  @AppStorage("showKeyboardHelpOverlay") private var showKeyboardHelpOverlay: Bool = true
  @AppStorage("enableLiveText") private var enableLiveText: Bool = false
  @AppStorage("enableDivinaImageContextMenu")
  private var enableDivinaImageContextMenu: Bool = AppConfig.enableDivinaImageContextMenu
  @AppStorage("showDivinaControlsGradientBackground")
  private var showControlsGradientBackground: Bool =
    AppConfig.showDivinaControlsGradientBackground
  @AppStorage("showDivinaProgressBarWhileReading")
  private var showProgressBarWhileReading: Bool =
    AppConfig.showDivinaProgressBarWhileReading
  @AppStorage("doubleTapZoomScale") private var doubleTapZoomScale: Double = 3.0
  @AppStorage("doubleTapZoomMode") private var doubleTapZoomMode: DoubleTapZoomMode = .enabled
  @AppStorage("shakeToOpenLiveText") private var shakeToOpenLiveText: Bool = false
  @AppStorage("divinaPreloadProfile") private var divinaPreloadProfile: ReaderPreloadProfile = .balanced
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("offlineFirstReading") private var offlineFirstReading: Bool = false

  @State private var readingDirection: ReadingDirection
  @State private var pageLayout: PageLayout
  @State private var isolateCoverPage: Bool
  @State private var splitWidePageMode: SplitWidePageMode
  @State private var rotation: ReaderRotation

  private let logger = AppLogger(.reader)

  @State private var currentBookId: String
  @State private var viewModel: ReaderViewModel
  @State private var showingControls = false
  // Captures `shouldShowControls` on the active → non-active scene-phase
  // transition (before the force-show below flips `showingControls`), so the
  // subsequent resume can decide whether to auto-hide the overlay or leave it
  // visible. See `handleScenePhaseChange(from:to:)`.
  @State private var wasShowingControlsBeforeBackground: Bool = false
  // Task that fades the resume-triggered overlay back to hidden after a brief
  // glance window. Reset on user interaction (page change) to act as an idle
  // timeout; cancelled on tap-toggle and reader close. Nil when no auto-hide
  // is pending.
  @State private var autoHideAfterResumeTask: Task<Void, Never>?
  @State private var currentSeries: Series?
  @State private var currentBook: Book?
  @State private var seriesId: String?
  @State private var nextBook: Book?
  @State private var previousBook: Book?
  @State private var showTapZoneOverlay = false
  @State private var tapZoneOverlayTimer: Timer?

  @State private var showKeyboardHelp = false
  @State private var keyboardHelpTimer: Timer?
  @State private var preserveReaderOptions = false
  @State private var usesDualPagePresentation = false
  @State private var webtoonScrollController = WebtoonScrollController()
  @State private var readerSafeAreaTop: CGFloat = 0
  @State private var readerViewHeight: CGFloat = 0

  // UI Panels states
  @State private var showingPageJumpSheet = false
  @State private var showingTOCSheet = false
  @State private var showingReaderSettingsSheet = false
  @State private var showingDetailSheet = false
  @State private var requestedNextSegmentPreloads: Set<String> = []
  @State private var requestedPreviousSegmentPreloads: Set<String> = []
  @State private var inFlightNextSegmentPreloads: [String: Task<Void, Never>] = [:]
  @State private var inFlightPreviousSegmentPreloads: [String: Task<Void, Never>] = [:]
  @State private var deferredPageMaintenanceTask: Task<Void, Never>?
  @State private var deferredAdjacentBookTask: Task<Void, Never>?

  #if os(tvOS)
    @State private var lastTVRemoteMoveSignature: String = ""
    @State private var lastTVRemoteMoveTimestamp: TimeInterval = 0
    @State private var lastTVRemoteSelectTimestamp: TimeInterval = 0
    @State private var tvRemoteCaptureGeneration: Int = 0
  #endif

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
    self._currentBookId = State(initialValue: book.id)
    self._currentBook = State(initialValue: book)
    self._readingDirection = State(initialValue: AppConfig.defaultReadingDirection)
    self._pageLayout = State(initialValue: AppConfig.pageLayout)
    self._isolateCoverPage = State(initialValue: AppConfig.isolateCoverPage)
    self._splitWidePageMode = State(initialValue: AppConfig.splitWidePageMode)
    self._rotation = State(initialValue: .none)
    self._viewModel = State(
      initialValue: ReaderViewModel(
        isolateCoverPage: AppConfig.isolateCoverPage,
        pageLayout: AppConfig.pageLayout,
        splitWidePageMode: AppConfig.splitWidePageMode,
        pageTransitionStyle: AppConfig.pageTransitionStyle,
        rotation: .none,
        preloadWindow: AppConfig.divinaPreloadProfile.window,
        incognitoMode: incognito
      )
    )
  }

  var shouldShowControls: Bool {
    !viewModel.isZoomed && (!viewModel.hasPages || showingControls)
  }

  private var renderConfig: ReaderRenderConfig {
    ReaderRenderConfig(
      tapZoneMode: tapZoneMode,
      tapZoneInversionMode: tapZoneInversionMode,
      showPageNumber: showPageNumber,
      showPageShadow: showPageShadow,
      readerBackground: readerBackground,
      enableLiveText: enableLiveText,
      enableImageContextMenu: enableDivinaImageContextMenu,
      supportsPageIsolationActions: readingDirection != .webtoon
        && readingDirection != .vertical
        && pageLayout.supportsDualPageOptions,
      doubleTapZoomScale: doubleTapZoomScale,
      doubleTapZoomMode: doubleTapZoomMode
    )
  }

  private var currentSegmentContext:
    (
      bookId: String, currentBook: Book?, previousBook: Book?, nextBook: Book?
    )
  {
    viewModel.activeSegmentContext(
      fallbackBookId: currentBookId,
      fallbackCurrentBook: currentBook,
      fallbackPreviousBook: previousBook,
      fallbackNextBook: nextBook
    )
  }

  private var currentSegmentBookId: String {
    currentSegmentContext.bookId
  }

  private var currentTOCSelection: ReaderTOCSelection {
    viewModel.currentTOCSelection(
      in: viewModel.tableOfContents,
      for: currentSegmentBookId
    )
  }

  private var currentSegmentBook: Book? {
    currentSegmentContext.currentBook
  }

  private var currentSegmentNextBook: Book? {
    currentSegmentContext.nextBook
  }

  private var currentSegmentPreviousBook: Book? {
    currentSegmentContext.previousBook
  }

  private var showPageDimensionWarning: Bool {
    guard !isOffline, !offlineFirstReading else { return false }
    guard pageLayout.supportsDualPageOptions || splitWidePageMode.isEnabled else { return false }
    return viewModel.hasMissingPageDimensions(forBookId: currentSegmentBookId)
  }

  private var handoffBookId: String {
    currentSegmentBook?.id ?? currentBook?.id ?? book.id
  }

  private var handoffTitle: String {
    currentSegmentBook?.metadata.title ?? currentBook?.metadata.title ?? book.metadata.title
  }

  private var handoffPageNumber: Int? {
    viewModel.currentReaderPage?.pageNumber
  }

  private var isShowingEndPage: Bool {
    viewModel.currentViewItem()?.isEnd == true
  }

  private var pageTurnAnimationDuration: Double {
    animateTapTurns ? 0.3 : 0
  }

  private var isPresentingModalSheet: Bool {
    showingPageJumpSheet
      || showingTOCSheet
      || showingReaderSettingsSheet
      || showingDetailSheet
  }

  private var isKeyboardCaptureEnabled: Bool {
    !isPresentingModalSheet
  }

  private func shouldUseDualPage(screenSize: CGSize) -> Bool {
    guard screenSize.width > screenSize.height else { return false }  // Only in landscape
    guard pageLayout != .single else { return false }
    return readingDirection != .vertical
  }

  private func updateHandoff() {
    let url = KomgaWebLinkBuilder.bookReader(
      serverURL: current.serverURL,
      bookId: handoffBookId,
      pageNumber: handoffPageNumber,
      incognito: incognito
    )
    readerPresentation.updateHandoff(sessionID: sessionID, title: handoffTitle, url: url)
  }

  #if os(iOS)
    private func updateReaderLiveActivityProgress() {
      let segmentBookId = currentSegmentBookId
      let totalPages = viewModel.pageCount(forSegmentBookId: segmentBookId)
      guard totalPages > 0 else { return }
      let currentPage = viewModel.currentPageNumber(inSegmentBookId: segmentBookId) ?? 0
      ReaderLiveActivityManager.shared.updateReadingProgress(
        ReaderLiveActivityManager.normalizedPageProgress(
          currentPage: currentPage,
          totalPages: totalPages
        )
      )
    }
  #endif

  private func closeReader() {
    cancelAutoHideAfterResume()
    logger.debug(
      "🚪 Closing DIVINA reader for book \(currentBookId), currentPage=\(viewModel.currentPage?.number ?? -1), totalPages=\(viewModel.pageCount)"
    )
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
    // Capture pre-background overlay state once, on the active → non-active
    // edge, BEFORE the force-show below flips `showingControls`. This is what
    // tells `scheduleAutoHideAfterResume` whether the user was reading with
    // the overlay hidden (and therefore wants it back hidden after a glance)
    // or with it visible (and wants it to stay visible).
    if oldPhase == .active && newPhase != .active {
      wasShowingControlsBeforeBackground = autoHideAfterResumeTask == nil && shouldShowControls
      cancelAutoHideAfterResume()
    }

    // Force the overlay visible on every background → foreground cycle so
    // iOS's status-bar / safe-area state stays in a known configuration and
    // the dashboard inherits a clean safe-area on subsequent close. The
    // overlay flashing visible on every lock/unlock until tapped is what the
    // auto-hide below mitigates.
    if newPhase != .active || !shouldShowControls {
      showingControls = true
    }

    // On returning to .active: if pre-background was hidden, schedule a brief
    // auto-hide so the user gets a glance at title/progress and the overlay
    // fades back to where it was.
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
  /// on the resume path when the user had the overlay hidden before going to
  /// background; preserves visible-overlay sessions untouched. Sub-tasks are
  /// idempotent — re-scheduling cancels and replaces.
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
  /// existing user-interaction observers (e.g., page changes) so the auto-
  /// hide acts as an idle timeout: any interaction within the window resets
  /// the clock, and the overlay only fades when the user actually stops
  /// engaging. Does nothing when no auto-hide is pending (normal reading
  /// outside the post-resume window).
  private func resetAutoHideAfterResumeIfPending() {
    guard autoHideAfterResumeTask != nil else { return }
    scheduleAutoHideAfterResume()
  }

  private func schedulePageMaintenanceAfterPageChange() {
    deferredPageMaintenanceTask?.cancel()
    let delay: TimeInterval =
      readingDirection == .webtoon
      ? WebtoonConstants.postScrollCleanupDelay : 0
    deferredPageMaintenanceTask = Task(priority: .utility) {
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      guard !Task.isCancelled else { return }
      await viewModel.preloadPages()
      await preloadAdjacentSegmentsForCurrentPositionIfNeeded()
      await viewModel.ensureTableOfContentsForCurrentSegment()
    }
  }

  private func resetReaderPreferencesForCurrentBook() {
    pageLayout = AppConfig.pageLayout
    viewModel.updatePageLayout(pageLayout)
    isolateCoverPage = AppConfig.isolateCoverPage
    splitWidePageMode = AppConfig.splitWidePageMode
    viewModel.updateSplitWidePageMode(splitWidePageMode)
    readingDirection = AppConfig.defaultReadingDirection
  }

  private func screenKey(screenSize: CGSize) -> String {
    return "\(Int(screenSize.width))x\(Int(screenSize.height))"
  }

  private func readerViewportSize(containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGSize {
    #if os(iOS) || os(tvOS)
      CGSize(
        width: max(0, containerSize.width + safeAreaInsets.leading + safeAreaInsets.trailing),
        height: max(0, containerSize.height + safeAreaInsets.top + safeAreaInsets.bottom)
      )
    #else
      containerSize
    #endif
  }

  private func readerViewportOffset(safeAreaInsets: EdgeInsets) -> CGSize {
    #if os(iOS) || os(tvOS)
      CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
    #else
      .zero
    #endif
  }

  private func readerPresentationKey(useDualPage: Bool) -> String {
    [
      readingDirection.rawValue,
      pageTransitionStyle.rawValue,
      pageLayout.rawValue,
      isolateCoverPage.description,
      splitWidePageMode.rawValue,
      String(useDualPage),
    ].joined(separator: "-")
  }

  private func readerContentKey(useDualPage: Bool) -> String {
    [
      currentBookId,
      readerPresentationKey(useDualPage: useDualPage),
    ].joined(separator: "-")
  }

  private func applyDualPagePresentationMode(_ useDualPage: Bool) {
    viewModel.updateDualPagePresentationMode(useDualPage)
  }

  #if os(tvOS)
    private var shouldEnableUIKitRemoteCapture: Bool {
      !showingPageJumpSheet
        && !showingTOCSheet
        && !showingReaderSettingsSheet
        && !showingDetailSheet
        && viewModel.hasPages
    }

    private func readerNavigationStep(forTVMove direction: MoveCommandDirection) -> ReaderNavigationStep? {
      switch readingDirection {
      case .ltr:
        switch direction {
        case .left:
          return .previous
        case .right:
          return .next
        default:
          return nil
        }
      case .rtl:
        switch direction {
        case .left:
          return .next
        case .right:
          return .previous
        default:
          return nil
        }
      case .vertical, .webtoon:
        switch direction {
        case .up:
          return .previous
        case .down:
          return .next
        default:
          return nil
        }
      }
    }

    private func shouldIgnoreDuplicateTVSelectCommand() -> Bool {
      let now = Date().timeIntervalSinceReferenceDate
      let isDuplicate = now - lastTVRemoteSelectTimestamp < 0.08
      lastTVRemoteSelectTimestamp = now
      return isDuplicate
    }

    private func shouldIgnoreDuplicateTVMoveCommand(_ direction: MoveCommandDirection) -> Bool {
      let now = Date().timeIntervalSinceReferenceDate
      let signature = String(describing: direction)
      let isDuplicate =
        lastTVRemoteMoveSignature == signature
        && now - lastTVRemoteMoveTimestamp < 0.08

      if isDuplicate {
        return true
      }

      lastTVRemoteMoveSignature = signature
      lastTVRemoteMoveTimestamp = now
      return false
    }

    private func handleTVMoveCommand(_ direction: MoveCommandDirection, source: String) -> Bool {
      logger.debug(
        "📺 \(source) move direction=\(String(describing: direction)), showingControls=\(showingControls), currentPageID=\(String(describing: viewModel.currentReaderPage?.id)), totalPages=\(viewModel.pageCount)"
      )

      if showingControls {
        logger.debug("📺 \(source) move ignored: controls are visible")
        return false
      }
      if !viewModel.hasPages {
        logger.debug("📺 \(source) move ignored: pages are empty")
        return false
      }

      if shouldIgnoreDuplicateTVMoveCommand(direction) {
        logger.debug("📺 \(source) move ignored: duplicate command")
        return true
      }

      if isShowingEndPage {
        if let step = readerNavigationStep(forTVMove: direction) {
          logger.debug("📺 \(source) move on end page: go to \(String(describing: step)) page")
          goToReaderPosition(step)
          return true
        }

        logger.debug("📺 \(source) move ignored on end page: unsupported direction")
        return false
      }

      guard let step = readerNavigationStep(forTVMove: direction) else {
        return false
      }
      goToReaderPosition(step)
      return true
    }

    private func handleTVSelectCommand(source: String) -> Bool {
      logger.debug(
        "📺 \(source) select, showingControls=\(showingControls), totalPages=\(viewModel.pageCount), currentPageID=\(String(describing: viewModel.currentReaderPage?.id))"
      )

      if shouldIgnoreDuplicateTVSelectCommand() {
        logger.debug("📺 \(source) select ignored: duplicate command")
        return true
      }

      if showingControls {
        logger.debug("📺 \(source) select ignored: controls are visible")
        return false
      }
      if !viewModel.hasPages {
        logger.debug("📺 \(source) select ignored: pages are empty")
        return false
      }
      if isShowingEndPage {
        logger.debug("📺 \(source) select on end page: toggle controls")
        toggleControls()
        return true
      }

      toggleControls()
      return true
    }
  #endif

  private var readerIsReadyForHints: Bool {
    viewModel.hasPages && !viewModel.isLoading
  }

  var body: some View {
    GeometryReader { geometry in
      let containerSize = geometry.size
      let safeAreaInsets = geometry.safeAreaInsets
      let screenSize = readerViewportSize(containerSize: containerSize, safeAreaInsets: safeAreaInsets)
      let screenOffset = readerViewportOffset(safeAreaInsets: safeAreaInsets)
      let screenKey = screenKey(screenSize: screenSize)
      let useDualPage = shouldUseDualPage(screenSize: screenSize)

      ZStack(alignment: .topLeading) {
        readerSurface(
          useDualPage: useDualPage,
          screenSize: screenSize,
          screenKey: screenKey
        )
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .offset(x: screenOffset.width, y: screenOffset.height)

        controlsOverlay(useDualPage: useDualPage)
          .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)

        keyboardHelpOverlay
      }
      .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
      .onGeometryChange(for: CGFloat.self) {
        $0.safeAreaInsets.top
      } action: {
        readerSafeAreaTop = $0
      }
      .onGeometryChange(for: CGFloat.self) {
        #if os(iOS) || os(tvOS)
          $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
        #else
          $0.size.height
        #endif
      } action: {
        readerViewHeight = $0
      }
      .onChange(of: useDualPage, initial: true) { _, newValue in
        usesDualPagePresentation = newValue
        applyDualPagePresentationMode(newValue)
      }
      #if os(tvOS)
        .onPlayPauseCommand {
          logger.debug("📺 onPlayPauseCommand: toggling controls, showingControls=\(showingControls)")
          toggleControls()
        }
        .onExitCommand {
          logger.debug("📺 onExitCommand: showingControls=\(showingControls)")
          handleReaderExitCommand()
        }
      #endif
      .background(
        keyboardCaptureView
      )
    }
    .iPadIgnoresSafeArea()
    #if os(iOS)
      .statusBarHidden(!shouldShowControls)
      .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
        if shakeToOpenLiveText {
          enableLiveText.toggle()
          let message = enableLiveText ? String(localized: "Live Text: ON") : String(localized: "Live Text: OFF")
          ErrorManager.shared.notify(message: message)
        }
      }
    #endif
    .sheet(isPresented: $showingPageJumpSheet) {
      PageJumpSheetView(
        segmentBookId: currentSegmentBookId,
        currentPageID: viewModel.currentReaderPage?.id,
        readingDirection: readingDirection,
        viewModel: viewModel,
        onJump: jumpToPageID
      )
    }
    .sheet(isPresented: $showingTOCSheet) {
      DivinaTOCSheetView(
        entries: viewModel.tableOfContents,
        currentEntryIDs: currentTOCSelection.entryIDs,
        scrollTargetID: currentTOCSelection.scrollTargetID,
        onSelect: { entry in
          showingTOCSheet = false
          jumpToTOCEntry(entry)
        }
      )
    }
    .sheet(isPresented: $showingReaderSettingsSheet) {
      ReaderSettingsSheet(readingDirection: readingDirection)
    }
    .readerDetailSheet(
      isPresented: $showingDetailSheet,
      book: currentSegmentBook,
      series: currentSeries
    )
    .onAppear {
      viewModel.updateDualPageSettings(noCover: !isolateCoverPage)
      updateHandoff()
      #if os(macOS)
        configureReaderCommands()
      #endif
    }
    .onChange(of: isolateCoverPage) { _, newValue in
      viewModel.updateDualPageSettings(noCover: !newValue)
    }
    .onChange(of: pageLayout) { _, newValue in
      viewModel.updatePageLayout(newValue)
    }
    .onChange(of: splitWidePageMode) { _, newValue in
      viewModel.updateSplitWidePageMode(newValue)
    }
    .onChange(of: pageTransitionStyle) { _, newValue in
      viewModel.updatePageTransitionStyle(newValue)
    }
    .onChange(of: rotation) { _, newValue in
      viewModel.updateRotation(newValue)
    }
    .onChange(of: divinaPreloadProfile) { _, newValue in
      viewModel.updatePreloadWindow(newValue.window)
    }
    .task(id: currentBookId) {
      readerPresentation.registerFlushHandler(for: sessionID) {
        viewModel.flushProgress()
      }
      deferredPageMaintenanceTask?.cancel()
      deferredPageMaintenanceTask = nil
      deferredAdjacentBookTask?.cancel()
      deferredAdjacentBookTask = nil
      requestedNextSegmentPreloads.removeAll()
      requestedPreviousSegmentPreloads.removeAll()
      inFlightNextSegmentPreloads.values.forEach { $0.cancel() }
      inFlightPreviousSegmentPreloads.values.forEach { $0.cancel() }
      inFlightNextSegmentPreloads.removeAll()
      inFlightPreviousSegmentPreloads.removeAll()
      if !preserveReaderOptions {
        resetReaderPreferencesForCurrentBook()
      }
      await loadBook(bookId: currentBookId, preserveReaderOptions: preserveReaderOptions)
      preserveReaderOptions = false
    }
    .onChange(of: currentBook?.id) { _, _ in
      updateHandoff()
    }
    .onChange(of: currentBook) { _, newBook in
      guard let newBook else { return }
      readerPresentation.updatePresentedBook(sessionID: sessionID, book: newBook)
    }
    .onChange(of: viewModel.pageCount) { oldCount, newCount in
      if oldCount == 0 && newCount > 0 && readerIsReadyForHints {
        triggerTapZoneOverlay(timeout: 1)
        triggerKeyboardHelp(timeout: 1.5)
      }
    }
    .onChange(of: viewModel.isLoading) { _, isLoading in
      if isLoading {
        hideTapZoneOverlay()
        hideKeyboardHelp()
      } else if readerIsReadyForHints {
        triggerTapZoneOverlay(timeout: 1)
        triggerKeyboardHelp(timeout: 1.5)
      }
    }
    .onDisappear {
      logger.debug(
        "👋 DIVINA reader disappeared for book \(currentBookId), currentPage=\(viewModel.currentPage?.number ?? -1), totalPages=\(viewModel.pageCount)"
      )
      tapZoneOverlayTimer?.invalidate()
      keyboardHelpTimer?.invalidate()
      deferredPageMaintenanceTask?.cancel()
      deferredPageMaintenanceTask = nil
      deferredAdjacentBookTask?.cancel()
      deferredAdjacentBookTask = nil
      inFlightNextSegmentPreloads.values.forEach { $0.cancel() }
      inFlightPreviousSegmentPreloads.values.forEach { $0.cancel() }
      inFlightNextSegmentPreloads.removeAll()
      inFlightPreviousSegmentPreloads.removeAll()
      viewModel.clearPreloadedImages()
      // Session-owned handlers are cleared on real teardown in ReaderPresentationManager.
      // This view-level disappear can fire during macOS fullscreen/remount setup.
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      handleScenePhaseChange(from: oldPhase, to: newPhase)
    }
    .onChange(of: viewModel.isZoomed) { _, newValue in
      if newValue {
        showingControls = false
      }
    }
    .onChange(of: readingDirection) { _, _ in
      #if os(iOS) || os(macOS)
        triggerTapZoneOverlay(timeout: 1)
      #endif
    }
    #if os(tvOS)
      .onChange(of: shouldEnableUIKitRemoteCapture) { oldValue, newValue in
        if newValue && !oldValue {
          tvRemoteCaptureGeneration += 1
          logger.debug("📺 UIKit capture enabled, restart generation=\(tvRemoteCaptureGeneration)")
        }
      }
    #endif
    #if os(macOS)
      .onChange(of: readerCommandState) { _, newState in
        readerPresentation.updateReaderCommandState(newState)
      }
    #endif
    #if os(iOS)
      .readerDismissGesture(readingDirection: readingDirection)
    #endif
  }

  private func readerSurface(
    useDualPage: Bool,
    screenSize: CGSize,
    screenKey: String
  ) -> some View {
    ZStack(alignment: .topLeading) {
      readerBackground.color

      readerContent(
        useDualPage: useDualPage,
        screenSize: screenSize
      )
      .frame(width: screenSize.width, height: screenSize.height)

      #if os(tvOS)
        tvRemoteCommandOverlay
      #endif

      helperOverlay(screenKey: screenKey)
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
    }
    .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
  }

  @ViewBuilder
  private func readerContent(
    useDualPage: Bool,
    screenSize: CGSize
  ) -> some View {
    let showsLoadedContent = viewModel.hasPages && !viewModel.isLoading

    ZStack {
      if viewModel.hasPages {
        loadedReaderContent(useDualPage: useDualPage, screenSize: screenSize)
          .readerLoadingContent(isVisible: showsLoadedContent)
      } else if !viewModel.isLoading {
        NoPagesView(onDismiss: { closeReader() })
          .transition(ReaderLoadingTransition.content)
      }

      if viewModel.isLoading {
        ReaderLoadingView(
          title: viewModel.loadingTitle,
          detail: viewModel.loadingDetail,
          progress: viewModel.loadingProgress,
          cardFill: readerBackground.loadingCardFill,
          contentColor: readerBackground.loadingContentColor
        )
        .readerLoadingOverlay()
      }
    }
    .animation(ReaderLoadingTransition.animation, value: viewModel.isLoading)
    .animation(ReaderLoadingTransition.animation, value: viewModel.hasPages)
    .onChange(of: viewModel.currentReaderPage?.id) { oldPageID, newPageID in
      handleReaderPageChange(from: oldPageID, to: newPageID)
    }
  }

  @ViewBuilder
  private func loadedReaderContent(
    useDualPage: Bool,
    screenSize: CGSize
  ) -> some View {
    let contentKey = readerContentKey(useDualPage: useDualPage)

    Group {
      if readingDirection == .webtoon {
        #if os(iOS) || os(macOS)
          WebtoonPageView(
            viewModel: viewModel,
            readListContext: readListContext,
            onDismiss: { closeReader() },
            onTapZoneTap: handleTapZoneTap,
            scrollController: webtoonScrollController,
            pageWidthPercentage: webtoonPageWidthPercentage,
            renderConfig: renderConfig
          )
        #else
          ScrollPageView(
            mode: .vertical,
            viewportSize: screenSize,
            readingDirection: readingDirection,
            splitWidePageMode: splitWidePageMode,
            navigationAnimationDuration: pageTurnAnimationDuration,
            renderConfig: renderConfig,
            viewModel: viewModel,
            readListContext: readListContext,
            onDismiss: { closeReader() },
            onTapZoneTap: handleTapZoneTap
          )
        #endif
      } else {
        switch pageTransitionStyle {
        case .pageCurl:
          #if os(iOS)
            if useDualPage {
              CurlDualPageView(
                viewModel: viewModel,
                mode: PageViewMode(direction: readingDirection, useDualPage: useDualPage),
                readingDirection: readingDirection,
                splitWidePageMode: splitWidePageMode,
                animateTapTurns: animateTapTurns,
                renderConfig: renderConfig,
                readListContext: readListContext,
                onDismiss: { closeReader() },
                onTapZoneTap: handleTapZoneTap
              )
            } else {
              CurlPageView(
                viewModel: viewModel,
                mode: PageViewMode(direction: readingDirection, useDualPage: useDualPage),
                readingDirection: readingDirection,
                splitWidePageMode: splitWidePageMode,
                animateTapTurns: animateTapTurns,
                renderConfig: renderConfig,
                readListContext: readListContext,
                onDismiss: { closeReader() },
                onTapZoneTap: handleTapZoneTap
              )
            }
          #else
            standardScrollPageView(useDualPage: useDualPage, screenSize: screenSize)
          #endif
        case .scroll:
          standardScrollPageView(useDualPage: useDualPage, screenSize: screenSize)
        case .cover:
          NativeCoverPageView(
            mode: PageViewMode(direction: readingDirection, useDualPage: useDualPage),
            readingDirection: readingDirection,
            splitWidePageMode: splitWidePageMode,
            tapNavigationAnimationDuration: pageTurnAnimationDuration,
            renderConfig: renderConfig,
            viewModel: viewModel,
            readListContext: readListContext,
            onDismiss: { closeReader() },
            onTapZoneTap: handleTapZoneTap
          )
        }
      }
    }
    .readerIgnoresSafeArea()
    .id(contentKey)
    #if os(tvOS)
      .onChange(of: isShowingEndPage) { oldValue, newValue in
        if oldValue && !newValue {
          tvRemoteCaptureGeneration += 1
          logger.debug("📺 left end page, restart UIKit capture generation=\(tvRemoteCaptureGeneration)")
        }
      }
    #endif
  }

  private func handleReaderPageChange(
    from oldPageID: ReaderPageID?,
    to newPageID: ReaderPageID?
  ) {
    let previousSnapshot = viewModel.captureProgressSnapshot(for: oldPageID)
    let currentSnapshot = viewModel.captureProgressSnapshot(for: newPageID)
    if let newPageID {
      syncPresentedBookIfCrossedSegmentBoundary(toSegmentBookId: newPageID.bookId)
    }
    updateHandoff()
    #if os(iOS)
      updateReaderLiveActivityProgress()
    #endif
    viewModel.enqueueProgressChange(from: previousSnapshot, to: currentSnapshot)
    schedulePageMaintenanceAfterPageChange()
    // Treat page changes as user activity: if we're inside the post-
    // resume auto-hide window, restart the timer so the overlay stays
    // visible while the user is actively flipping pages and only fades
    // after a real pause.
    resetAutoHideAfterResumeIfPending()
  }

  @ViewBuilder
  private func standardScrollPageView(useDualPage: Bool, screenSize: CGSize) -> some View {
    ScrollPageView(
      mode: PageViewMode(direction: readingDirection, useDualPage: useDualPage),
      viewportSize: screenSize,
      readingDirection: readingDirection,
      splitWidePageMode: splitWidePageMode,
      navigationAnimationDuration: pageTurnAnimationDuration,
      renderConfig: renderConfig,
      viewModel: viewModel,
      readListContext: readListContext,
      onDismiss: { closeReader() },
      onTapZoneTap: handleTapZoneTap
    )
  }

  @ViewBuilder
  private func helperOverlay(screenKey: String) -> some View {
    #if os(iOS) || os(macOS)
      TapZoneOverlay(isVisible: $showTapZoneOverlay, readingDirection: readingDirection)
        .readerIgnoresSafeArea()
        .onChange(of: screenKey) {
          // Show helper overlay when screen orientation changes
          triggerTapZoneOverlay(timeout: 1)
        }
        .onChange(of: tapZoneMode) {
          // Show helper overlay when tap zone mode changes
          triggerTapZoneOverlay(timeout: 1)
        }
        .onChange(of: tapZoneInversionMode) {
          // Show helper overlay when tap zone mirroring changes
          triggerTapZoneOverlay(timeout: 1)
        }
    #else
      EmptyView()
    #endif
  }

  #if os(tvOS)
    private var tvRemoteCommandOverlay: some View {
      TVRemoteCommandOverlay(
        isEnabled: shouldEnableUIKitRemoteCapture,
        commands: keyboardCommands,
        onMoveCommand: { direction in
          handleTVMoveCommand(direction, source: "uikit.overlay")
        },
        onSelectCommand: {
          handleTVSelectCommand(source: "uikit.overlay")
        },
        onKeyPress: { event in
          handleKeyboardEvent(event)
        }
      )
      .readerIgnoresSafeArea()
      .accessibilityHidden(true)
      .id(tvRemoteCaptureGeneration)
    }
  #endif

  private func controlsOverlay(useDualPage: Bool) -> some View {
    DivinaControlsOverlayView(
      readingDirection: $readingDirection,
      pageLayout: $pageLayout,
      isolateCoverPage: $isolateCoverPage,
      splitWidePageMode: $splitWidePageMode,
      rotation: $rotation,
      showingPageJumpSheet: $showingPageJumpSheet,
      showingTOCSheet: $showingTOCSheet,
      showingReaderSettingsSheet: $showingReaderSettingsSheet,
      showingDetailSheet: $showingDetailSheet,
      viewModel: viewModel,
      currentBook: currentSegmentBook,
      dualPage: useDualPage,
      incognito: incognito,
      onDismiss: { closeReader() },
      previousBook: currentSegmentPreviousBook,
      nextBook: currentSegmentNextBook,
      onPreviousBook: { openPreviousBook(previousBookId: $0) },
      onNextBook: { openNextBook(nextBookId: $0) },
      controlsVisible: shouldShowControls,
      showingControls: showingControls,
      showGradientBackground: showControlsGradientBackground,
      showProgressBarWhileReading: showProgressBarWhileReading,
      showPageDimensionWarning: showPageDimensionWarning
    )
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

    if viewModel.hasPages {
      commands.append(
        ReaderKeyboardCommand(
          title: "Jump to Page",
          event: ReaderKeyboardEvent(key: .j, modifiers: [.command])
        )
      )
    }

    return commands
  }

  @ViewBuilder
  private var keyboardCaptureView: some View {
    #if os(tvOS)
      EmptyView()
    #else
      KeyboardEventHandler(
        isEnabled: isKeyboardCaptureEnabled,
        commands: keyboardCommands,
        onKeyPress: handleKeyboardEvent
      )
    #endif
  }

  private var keyboardHelpOverlay: some View {
    KeyboardHelpOverlay(
      readingDirection: readingDirection,
      hasTOC: !viewModel.tableOfContents.isEmpty,
      supportsFullscreenToggle: supportsFullscreenToggle,
      supportsLiveText: supportsLiveTextKeyboardShortcut,
      supportsJumpToPage: true,
      supportsToggleControls: true,
      hasNextBook: currentSegmentNextBook != nil,
      isInteractive: keyboardHelpOverlayIsInteractive,
      onDismiss: {
        hideKeyboardHelp()
      }
    )
    .opacity(showKeyboardHelp ? 1.0 : 0.0)
    .allowsHitTesting(showKeyboardHelp && keyboardHelpOverlayIsInteractive)
    .animation(.default, value: showKeyboardHelp)
  }

  private var keyboardHelpOverlayIsInteractive: Bool {
    #if os(tvOS)
      false
    #else
      true
    #endif
  }

  private func handleKeyboardEvent(_ event: ReaderKeyboardEvent) -> Bool {
    if event.matches(.escape) {
      handleReaderExitCommand()
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
        showingTOCSheet = true
      }
      return true
    }

    if event.matches(.j, modifiers: [.command]) {
      if viewModel.hasPages {
        showingPageJumpSheet = true
      }
      return true
    }

    guard !event.hasSystemModifiers else { return false }

    if event.matches(.c) {
      toggleControls()
      return true
    }

    #if os(iOS) || os(macOS)
      if event.matches(.l) {
        enableLiveText.toggle()
        let message = enableLiveText ? String(localized: "Live Text: ON") : String(localized: "Live Text: OFF")
        ErrorManager.shared.notify(message: message)
        return true
      }
    #endif

    if event.matches(.t) {
      if !viewModel.tableOfContents.isEmpty {
        showingTOCSheet = true
      }
      return true
    }

    if event.matches(.j) {
      if viewModel.hasPages {
        showingPageJumpSheet = true
      }
      return true
    }

    if event.matches(.n) {
      if let nextBook = currentSegmentNextBook {
        openNextBook(nextBookId: nextBook.id)
      }
      return true
    }

    guard viewModel.hasPages else { return false }

    switch readingDirection {
    case .ltr:
      switch event.key {
      case .rightArrow:
        goToReaderPosition(.next)
        return true
      case .leftArrow:
        goToReaderPosition(.previous)
        return true
      default:
        return false
      }
    case .rtl:
      switch event.key {
      case .leftArrow:
        goToReaderPosition(.next)
        return true
      case .rightArrow:
        goToReaderPosition(.previous)
        return true
      default:
        return false
      }
    case .vertical:
      switch event.key {
      case .downArrow:
        goToReaderPosition(.next)
        return true
      case .upArrow:
        goToReaderPosition(.previous)
        return true
      default:
        return false
      }
    case .webtoon:
      switch event.key {
      case .downArrow:
        goToReaderPosition(.next)
        return true
      case .upArrow:
        goToReaderPosition(.previous)
        return true
      default:
        return false
      }
    }
  }

  private func sendWebtoonScrollCommand(for step: ReaderNavigationStep) {
    let direction: WebtoonScrollDirection =
      switch step {
      case .previous:
        .up
      case .next:
        .down
      }
    webtoonScrollController.scroll(direction)
  }

  private func loadBook(bookId: String, preserveReaderOptions: Bool) async {
    // Mark that loading has started
    viewModel.isLoading = true

    // Set incognito mode
    viewModel.incognitoMode = incognito

    // Load book info to get read progress page and series reading direction
    var initialPageNumber: Int? = nil

    // Resolve from in-memory/DB first, then always refresh from network when online.
    var resolvedBook: Book?
    let database = await DatabaseOperator.databaseIfConfigured()
    if let currentBook, currentBook.id == bookId {
      resolvedBook = currentBook
    } else if let cachedBook = await database?.fetchBook(id: bookId) {
      resolvedBook = cachedBook
    } else if book.id == bookId {
      resolvedBook = book
    }

    if !AppConfig.isOffline {
      if let syncedBook = try? await SyncService.syncBook(bookId: bookId) {
        resolvedBook = syncedBook
      }
    }

    if let resolvedBook {
      currentBook = resolvedBook
      seriesId = resolvedBook.seriesId
      if !incognito {
        readerPresentation.trackVisitedBook(
          sessionID: sessionID,
          bookId: resolvedBook.id,
          seriesId: resolvedBook.seriesId
        )
      }
      if incognito {
        initialPageNumber = nil
      } else if resolvedBook.isCompleted {
        initialPageNumber = nil
      } else {
        initialPageNumber = resolvedBook.readProgress?.page
      }
    }

    if let activeBook = currentBook {
      let isBookDownloaded = await OfflineManager.shared.isBookDownloaded(bookId: activeBook.id)

      // Refresh Divina manifest only when online and the book is not downloaded offline.
      if !AppConfig.isOffline, !isBookDownloaded {
        do {
          let manifest = try await BookService.getBookManifest(id: activeBook.id)
          let toc = await ReaderManifestService(bookId: activeBook.id).parseTOC(manifest: manifest)
          await database?.updateBookTOC(bookId: activeBook.id, toc: toc)
        } catch {
          // Silently fail - we'll use cached manifest
        }
      }

      // 3. Try to get series from DB
      var series = await database?.fetchSeries(id: activeBook.seriesId)
      if series == nil && !AppConfig.isOffline {
        series = try? await SyncService.syncSeriesDetail(seriesId: activeBook.seriesId)
      }

      if let series = series {
        currentSeries = series
        let preferredDirection: ReadingDirection
        if AppConfig.forceDefaultReadingDirection {
          preferredDirection = AppConfig.defaultReadingDirection
        } else {
          let rawReadingDirection = series.metadata.readingDirection?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
          if let rawReadingDirection, !rawReadingDirection.isEmpty {
            preferredDirection = ReadingDirection.fromString(rawReadingDirection)
          } else {
            preferredDirection = AppConfig.defaultReadingDirection
          }
        }

        if !preserveReaderOptions {
          readingDirection = preferredDirection.isSupported ? preferredDirection : .vertical
        }
      }

      // 4. Defer adjacent-book resolution to a background task. The two server
      // round trips (`/books/{id}/previous` + `/.../next`) account for ~2/3 of the
      // open-time network latency on a typical setup, but neither result affects
      // the initial render — `previousBook`/`nextBook` are consumed only by
      // post-open features (next/prev navigation buttons, end-page hints,
      // adjacent-segment preloading). The active segment's `activeSegmentContext`
      // already falls back to the view's @State when the segment metadata is nil,
      // so the open path doesn't need to wait on these.
      self.previousBook = nil
      self.nextBook = nil
      deferredAdjacentBookTask?.cancel()
      deferredAdjacentBookTask = Task { [bookId] in
        let adjacentBooks = await resolveAdjacentBooks(for: bookId)
        guard !Task.isCancelled, currentBookId == bookId else { return }
        previousBook = adjacentBooks.previous
        nextBook = adjacentBooks.next
        // Also write the resolved values back into the segment so `resolveSegmentPreloadContext`
        // does not redundantly re-fetch when the user navigates near the start/end.
        viewModel.updateAdjacentBooksForSegment(
          bookId: bookId,
          previousBook: adjacentBooks.previous,
          nextBook: adjacentBooks.next
        )
      }
    }

    let resumePageNumber = viewModel.currentPage?.number ?? initialPageNumber

    guard let activeBook = currentBook, activeBook.id == bookId else {
      viewModel.isLoading = false
      return
    }

    await viewModel.loadPages(
      book: activeBook,
      initialPageNumber: resumePageNumber,
      previousBook: nil,
      nextBook: nil
    )

    // Only preload pages if pages are available
    if !viewModel.hasPages {
      return
    }
    await viewModel.preloadPages()
    await preloadAdjacentSegmentsForCurrentPositionIfNeeded()
  }

  private func resolveAdjacentBooks(for bookId: String) async -> (previous: Book?, next: Book?) {
    let readListId = readListContext?.id
    let instanceId = AppConfig.current.instanceId
    let database = await DatabaseOperator.databaseIfConfigured()

    let resolvedNextBook = await resolveAdjacentBook(
      direction: .next,
      bookId: bookId,
      readListId: readListId,
      instanceId: instanceId,
      database: database
    )
    let resolvedPreviousBook = await resolveAdjacentBook(
      direction: .previous,
      bookId: bookId,
      readListId: readListId,
      instanceId: instanceId,
      database: database
    )

    return (resolvedPreviousBook, resolvedNextBook)
  }

  private enum AdjacentBookDirection {
    case previous
    case next
  }

  private func resolveAdjacentBook(
    direction: AdjacentBookDirection,
    bookId: String,
    readListId: String?,
    instanceId: String,
    database: DatabaseOperator?
  ) async -> Book? {
    if AppConfig.isOffline {
      return await cachedAdjacentBook(
        direction: direction,
        bookId: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }

    do {
      let resolvedBook: Book?
      switch direction {
      case .previous:
        resolvedBook = try await BookService.getPreviousBook(
          bookId: bookId,
          readListId: readListId
        )
      case .next:
        resolvedBook = try await NextBookToReadResolver.resolve(
          after: bookId,
          readListId: readListId,
          instanceId: instanceId
        )
      }

      if let resolvedBook, let database {
        await database.upsertBook(dto: resolvedBook, instanceId: instanceId)
      }
      return resolvedBook
    } catch {
      logger.warning(
        "⚠️ Failed to resolve \(direction == .next ? "next" : "previous") book from server for \(bookId): \(error)"
      )
      return await cachedAdjacentBook(
        direction: direction,
        bookId: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }
  }

  private func cachedAdjacentBook(
    direction: AdjacentBookDirection,
    bookId: String,
    readListId: String?,
    instanceId: String,
    database: DatabaseOperator?
  ) async -> Book? {
    switch direction {
    case .previous:
      return await database?.getPreviousBook(
        instanceId: instanceId,
        bookId: bookId,
        readListId: readListId
      )
    case .next:
      guard let database else { return nil }
      return await NextBookToReadResolver.resolveLocally(
        after: bookId,
        readListId: readListId,
        instanceId: instanceId,
        database: database
      )
    }
  }

  private var segmentPreloadTriggerDistance: Int {
    // Next-segment preload must also cover an offline-first download, so it
    // starts early enough to finish before the reader reaches the end page.
    5
  }

  private func resolveSegmentPreloadContext(for segmentBookId: String) async -> (
    currentBook: Book, previousBook: Book?, nextBook: Book?
  )? {
    guard let segmentBook = viewModel.currentBook(forSegmentBookId: segmentBookId) else { return nil }

    var resolvedPreviousBook = viewModel.previousBook(forSegmentBookId: segmentBookId)
    var resolvedNextBook = viewModel.nextBook(forSegmentBookId: segmentBookId)

    if resolvedPreviousBook == nil || resolvedNextBook == nil {
      let adjacentBooks = await resolveAdjacentBooks(for: segmentBookId)
      resolvedPreviousBook = resolvedPreviousBook ?? adjacentBooks.previous
      resolvedNextBook = resolvedNextBook ?? adjacentBooks.next
    }

    return (
      currentBook: segmentBook,
      previousBook: resolvedPreviousBook,
      nextBook: resolvedNextBook
    )
  }

  private func resolveBookBefore(_ book: Book) async -> Book? {
    if let cachedPreviousBook = viewModel.previousBook(forSegmentBookId: book.id) {
      return cachedPreviousBook
    }
    let previousAdjacentBooks = await resolveAdjacentBooks(for: book.id)
    return previousAdjacentBooks.previous
  }

  private func preloadAdjacentSegmentsForCurrentPositionIfNeeded() async {
    await preloadPreviousSegmentForCurrentPositionIfNeeded()
    await preloadNextSegmentForCurrentPositionIfNeeded()
  }

  private func preloadPreviousSegmentForCurrentPositionIfNeeded() async {
    guard let currentReaderPage = viewModel.currentReaderPage else { return }
    let segmentBookId = currentReaderPage.bookId

    guard let pagesFromSegmentStart = viewModel.currentPageOffsetInSegment(for: segmentBookId) else {
      return
    }
    guard pagesFromSegmentStart <= segmentPreloadTriggerDistance else { return }
    await ensurePreviousSegmentPreloaded(for: segmentBookId)
  }

  private func preloadNextSegmentForCurrentPositionIfNeeded() async {
    guard let currentReaderPage = viewModel.currentReaderPage else { return }
    let segmentBookId = currentReaderPage.bookId

    guard let remainingPagesInSegment = viewModel.remainingPagesInSegment(for: segmentBookId) else {
      return
    }
    guard remainingPagesInSegment <= segmentPreloadTriggerDistance else { return }
    await ensureNextSegmentPreloaded(for: segmentBookId)
  }

  @MainActor
  private func ensurePreviousSegmentPreloaded(for segmentBookId: String) async {
    guard !requestedPreviousSegmentPreloads.contains(segmentBookId) else { return }

    if let task = inFlightPreviousSegmentPreloads[segmentBookId] {
      await task.value
      return
    }

    let task = Task { @MainActor in
      guard
        let preloadContext = await resolveSegmentPreloadContext(for: segmentBookId),
        let resolvedPreviousBook = preloadContext.previousBook
      else {
        requestedPreviousSegmentPreloads.insert(segmentBookId)
        return
      }

      let resolvedPreviousPreviousBook = await resolveBookBefore(resolvedPreviousBook)

      await viewModel.preloadPreviousSegmentIfNeeded(
        currentBook: preloadContext.currentBook,
        previousBook: resolvedPreviousBook,
        nextBook: preloadContext.nextBook,
        previousPreviousBook: resolvedPreviousPreviousBook
      )

      if viewModel.currentBook(forSegmentBookId: resolvedPreviousBook.id) != nil {
        requestedPreviousSegmentPreloads.insert(segmentBookId)
      }
    }

    inFlightPreviousSegmentPreloads[segmentBookId] = task
    await task.value
    inFlightPreviousSegmentPreloads.removeValue(forKey: segmentBookId)
  }

  @MainActor
  private func ensureNextSegmentPreloaded(for segmentBookId: String) async {
    guard !requestedNextSegmentPreloads.contains(segmentBookId) else { return }

    if let task = inFlightNextSegmentPreloads[segmentBookId] {
      await task.value
      return
    }

    let task = Task { @MainActor in
      guard
        let preloadContext = await resolveSegmentPreloadContext(for: segmentBookId),
        let resolvedNextBook = preloadContext.nextBook
      else {
        requestedNextSegmentPreloads.insert(segmentBookId)
        return
      }

      await viewModel.preloadNextSegmentIfNeeded(
        currentBook: preloadContext.currentBook,
        previousBook: preloadContext.previousBook,
        nextBook: resolvedNextBook
      )

      if viewModel.currentBook(forSegmentBookId: resolvedNextBook.id) != nil {
        requestedNextSegmentPreloads.insert(segmentBookId)
      }
    }

    inFlightNextSegmentPreloads[segmentBookId] = task
    await task.value
    inFlightNextSegmentPreloads.removeValue(forKey: segmentBookId)
  }

  @MainActor
  private func navigateAcrossBoundaryIfNeeded(offset: Int) async -> Bool {
    guard let currentReaderPage = viewModel.currentReaderPage else { return false }
    let segmentBookId = currentReaderPage.bookId

    switch offset {
    case -1:
      guard viewModel.currentPageOffsetInSegment(for: segmentBookId) == 0 else { return false }
      await ensurePreviousSegmentPreloaded(for: segmentBookId)
    case 1:
      guard viewModel.remainingPagesInSegment(for: segmentBookId) == 0 else { return false }
      await ensureNextSegmentPreloaded(for: segmentBookId)
    default:
      return false
    }

    guard let adjacentItem = viewModel.adjacentViewItem(offset: offset) else {
      return false
    }
    viewModel.requestNavigation(toViewItem: adjacentItem)
    return true
  }

  /// Keep the presented-book identity aligned with the committed reader page.
  /// The whole-book load anchor stays unchanged so seamless segment transitions
  /// do not retrigger the reader loading task.
  private func syncPresentedBookIfCrossedSegmentBoundary(toSegmentBookId newSegmentBookId: String) {
    guard newSegmentBookId != currentBook?.id,
      let newBook = viewModel.currentBook(forSegmentBookId: newSegmentBookId)
    else {
      return
    }
    currentBook = newBook
    if !incognito {
      readerPresentation.trackVisitedBook(
        sessionID: sessionID,
        bookId: newBook.id,
        seriesId: newBook.seriesId
      )
    }
  }

  private func jumpToPageID(_ pageID: ReaderPageID) {
    guard pageID != viewModel.currentReaderPage?.id else { return }
    viewModel.requestNavigation(toPageID: pageID)
  }

  private func displayPageNumber(for pageID: ReaderPageID) -> Int {
    viewModel.displayPageNumber(for: pageID) ?? pageID.pageNumber + 1
  }

  private func jumpToTOCEntry(_ entry: ReaderTOCEntry) {
    guard
      let targetPageID = viewModel.pageID(
        forSegmentBookId: currentSegmentBookId,
        pageNumberInSegment: entry.pageIndex + 1
      )
    else {
      return
    }
    jumpToPageID(targetPageID)
  }

  #if os(macOS)
    private var macPageIsolationActions: [ReaderPageIsolationActions.Action] {
      ReaderPageIsolationActions.resolve(
        supportsDualPageOptions: readingDirection != .webtoon
          && readingDirection != .vertical
          && pageLayout.supportsDualPageOptions,
        dualPage: usesDualPagePresentation,
        readingDirection: readingDirection,
        currentPageID: viewModel.currentReaderPage?.id,
        currentPairIDs: viewModel.currentViewItem()?.pagePairIDs,
        isCurrentPageWide: viewModel.isCurrentPageWide,
        isCurrentPageIsolated: viewModel.isCurrentPageIsolated,
        displayPageNumber: displayPageNumber(for:)
      )
    }

    private var macCommandPageIDs: [ReaderPageID] {
      if let pair = viewModel.currentViewItem()?.pagePairIDs {
        return [pair.first, pair.second].compactMap(\.self)
      }
      guard let pageID = viewModel.currentReaderPage?.id else { return [] }
      return [pageID]
    }

    private var macDisplayPageNumbersByID: [ReaderPageID: Int] {
      Dictionary(
        uniqueKeysWithValues: macCommandPageIDs.map { pageID in
          (pageID, displayPageNumber(for: pageID))
        })
    }

    private func sharePageFromCommand(_ pageID: ReaderPageID) {
      guard let image = viewModel.preloadedImage(for: pageID) else { return }
      let fileName = viewModel.page(for: pageID)?.fileName
      ImageShareHelper.share(image: image, fileName: fileName)
    }

    private var readerCommandState: ReaderCommandState {
      let supportsDualPageOptions =
        readingDirection != .webtoon
        && readingDirection != .vertical
        && pageLayout.supportsDualPageOptions

      let supportsSplitWidePageMode =
        readingDirection != .webtoon

      return ReaderCommandState(
        isActive: true,
        supportsReaderSettings: true,
        supportsBookDetails: currentSegmentBook != nil,
        hasPages: viewModel.hasPages,
        hasTableOfContents: !viewModel.tableOfContents.isEmpty,
        supportsPageJump: viewModel.hasPages,
        supportsBookNavigation: true,
        canOpenPreviousBook: currentSegmentPreviousBook != nil,
        canOpenNextBook: currentSegmentNextBook != nil,
        readingDirection: readingDirection,
        availableReadingDirections: ReadingDirection.availableCases,
        pageLayout: pageLayout,
        isolateCoverPage: isolateCoverPage,
        pageIsolationActions: macPageIsolationActions,
        commandPageIDs: macCommandPageIDs,
        displayPageNumbersByID: macDisplayPageNumbersByID,
        rotation: rotation,
        splitWidePageMode: splitWidePageMode,
        supportsSearch: false,
        canSearch: false,
        supportsReadingDirectionSelection: true,
        supportsPageLayoutSelection: true,
        supportsRotationSelection: readingDirection != .webtoon,
        supportsDualPageOptions: supportsDualPageOptions,
        supportsSplitWidePageMode: supportsSplitWidePageMode
      )
    }

    private func configureReaderCommands() {
      readerPresentation.configureReaderCommands(
        state: readerCommandState,
        handlers: ReaderCommandHandlers(
          showReaderSettings: {
            showingReaderSettingsSheet = true
          },
          showBookDetails: {
            if currentSegmentBook != nil {
              showingDetailSheet = true
            }
          },
          showTableOfContents: {
            if !viewModel.tableOfContents.isEmpty {
              showingTOCSheet = true
            }
          },
          showPageJump: {
            if viewModel.hasPages {
              showingPageJumpSheet = true
            }
          },
          showSearch: {},
          openPreviousBook: {
            if let previousBook = currentSegmentPreviousBook {
              openPreviousBook(previousBookId: previousBook.id)
            }
          },
          openNextBook: {
            if let nextBook = currentSegmentNextBook {
              openNextBook(nextBookId: nextBook.id)
            }
          },
          setReadingDirection: { direction in
            readingDirection = direction
          },
          setPageLayout: { layout in
            pageLayout = layout
          },
          toggleIsolateCoverPage: {
            isolateCoverPage.toggle()
          },
          toggleIsolatePage: { pageID in
            viewModel.toggleIsolatePage(pageID)
          },
          sharePage: { pageID in
            sharePageFromCommand(pageID)
          },
          setRotation: { newRotation in
            rotation = newRotation
          },
          setSplitWidePageMode: { mode in
            splitWidePageMode = mode
          },
          toggleContinuousScroll: {}
        )
      )
    }
  #endif

  // T-Split controls strip height below the safe-area top, in points. Adaptive:
  // thin while controls are hidden so the navigation halves stay large; taller
  // while they're shown so a band below the toolbar can toggle them back off (a
  // fixed strip sized to the toolbar leaves no tappable dismiss surface). Tunable;
  // the shown band clears the toolbar (~80pt iPhone, ~105pt iPad) plus a ~44pt
  // tap row, so dismiss stays comfortable on both.
  private static let tSplitSummonBand: CGFloat = 44
  private static let tSplitDismissBand: CGFloat = 150

  private func handleTapZoneTap(normalizedX: CGFloat, normalizedY: CGFloat) {
    let stripHeightFraction: CGFloat?
    if tapZoneMode == .tSplit, readerViewHeight > 0 {
      let band = shouldShowControls ? Self.tSplitDismissBand : Self.tSplitSummonBand
      stripHeightFraction = (readerSafeAreaTop + band) / readerViewHeight
    } else {
      stripHeightFraction = nil
    }
    let action = TapZoneHelper.action(
      normalizedX: normalizedX,
      normalizedY: normalizedY,
      tapZoneMode: tapZoneMode,
      tapZoneInversionMode: tapZoneInversionMode,
      readingDirection: readingDirection,
      stripHeightFraction: stripHeightFraction
    )
    handleTapZoneAction(action)
  }

  private func handleTapZoneAction(_ action: TapZoneAction) {
    guard viewModel.hasPages, !isPresentingModalSheet, !viewModel.isZoomed else { return }
    switch action {
    case .previous:
      goToReaderPosition(.previous)
    case .next:
      goToReaderPosition(.next)
    case .toggleControls:
      toggleControls()
    }
  }

  private func goToReaderPosition(_ step: ReaderNavigationStep) {
    guard viewModel.hasPages else { return }
    switch readingDirection {
    case .ltr, .rtl, .vertical:
      goToPagedReaderPosition(step)
    case .webtoon:
      sendWebtoonScrollCommand(for: step)
    }
  }

  private func goToPagedReaderPosition(_ step: ReaderNavigationStep) {
    let offset: Int =
      switch step {
      case .previous:
        -1
      case .next:
        1
      }

    if let item = viewModel.adjacentViewItem(offset: offset) {
      viewModel.requestNavigation(toViewItem: item)
    } else {
      Task { @MainActor in
        _ = await navigateAcrossBoundaryIfNeeded(offset: offset)
      }
    }
  }

  #if os(tvOS)
    private func toggleControls() {
      // On tvOS, allow toggling controls even at endpage to enable navigation back
      cancelAutoHideAfterResume()
      withAnimation {
        showingControls.toggle()
      }
    }
  #else
    private func toggleControls() {
      cancelAutoHideAfterResume()
      withAnimation {
        showingControls.toggle()
      }
    }
  #endif

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

  private var supportsLiveTextKeyboardShortcut: Bool {
    #if os(iOS) || os(macOS)
      true
    #else
      false
    #endif
  }

  private func handleReaderExitCommand() {
    #if os(tvOS)
      if showingControls {
        toggleControls()
        return
      }
    #endif
    closeReader()
  }

  /// Hide helper overlay and cancel timer
  private func hideTapZoneOverlay() {
    tapZoneOverlayTimer?.invalidate()
    withAnimation {
      showTapZoneOverlay = false
    }
  }

  /// Show reader helper overlay (Tap zones on iOS, keyboard help on macOS)
  private func triggerTapZoneOverlay(timeout: TimeInterval) {
    // Respect user preference and ensure we have content
    guard showTapZoneHints, readerIsReadyForHints else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      guard self.readerIsReadyForHints else { return }
      withAnimation {
        self.showTapZoneOverlay = true
      }
      self.resetTapZoneOverlayTimer(timeout: timeout)
    }
  }

  /// Auto-hide helper overlay after a platform-specific delay
  private func resetTapZoneOverlayTimer(timeout: TimeInterval) {
    tapZoneOverlayTimer?.invalidate()
    tapZoneOverlayTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
      DispatchQueue.main.async {
        self.hideTapZoneOverlay()
      }
    }
  }

  /// Hide keyboard help overlay and cancel timer
  private func hideKeyboardHelp() {
    keyboardHelpTimer?.invalidate()
    keyboardHelpTimer = nil
    withAnimation {
      showKeyboardHelp = false
    }
  }

  private func toggleKeyboardHelpManually() {
    keyboardHelpTimer?.invalidate()
    keyboardHelpTimer = nil
    withAnimation {
      showKeyboardHelp.toggle()
    }
  }

  /// Show keyboard help overlay
  private func triggerKeyboardHelp(timeout: TimeInterval) {
    // Respect user preference and ensure we have content
    guard showKeyboardHelpOverlay, readerIsReadyForHints else { return }
    guard ReaderKeyboardAvailability.shouldAutoShowKeyboardHelp else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      guard self.readerIsReadyForHints else { return }
      withAnimation {
        self.showKeyboardHelp = true
      }
      self.resetKeyboardHelpTimer(timeout: timeout)
    }
  }

  /// Auto-hide keyboard help overlay after a delay
  private func resetKeyboardHelpTimer(timeout: TimeInterval) {
    keyboardHelpTimer?.invalidate()
    keyboardHelpTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
      DispatchQueue.main.async {
        self.hideKeyboardHelp()
      }
    }
  }

  private func openNextBook(nextBookId: String) {
    logger.debug(
      "➡️ Opening next book from \(currentBookId) to \(nextBookId), flush current progress first"
    )
    viewModel.flushProgress()
    // Switch to next book by updating currentBookId
    // This will trigger the .task(id: currentBookId) to reload
    preserveReaderOptions = true
    currentBookId = nextBookId
    // Reset viewModel state for new book
    viewModel = ReaderViewModel(
      isolateCoverPage: isolateCoverPage,
      pageLayout: pageLayout,
      splitWidePageMode: splitWidePageMode,
      rotation: rotation,
      preloadWindow: divinaPreloadProfile.window,
      incognitoMode: incognito
    )
    // Reset overlay state
    hideTapZoneOverlay()
    hideKeyboardHelp()
  }

  private func openPreviousBook(previousBookId: String) {
    logger.debug(
      "⬅️ Opening previous book from \(currentBookId) to \(previousBookId), flush current progress first"
    )
    viewModel.flushProgress()
    // Switch to previous book by updating currentBookId
    // This will trigger the .task(id: currentBookId) to reload
    preserveReaderOptions = true
    currentBookId = previousBookId
    // Reset viewModel state for new book
    viewModel = ReaderViewModel(
      isolateCoverPage: isolateCoverPage,
      pageLayout: pageLayout,
      splitWidePageMode: splitWidePageMode,
      rotation: rotation,
      preloadWindow: divinaPreloadProfile.window,
      incognitoMode: incognito
    )
    // Reset overlay state
    hideTapZoneOverlay()
    hideKeyboardHelp()
  }

}
