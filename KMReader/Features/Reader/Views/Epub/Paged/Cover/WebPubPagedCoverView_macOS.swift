#if os(macOS)
  import AppKit
  import SwiftUI
  import WebKit

  struct WebPubPagedCoverView: NSViewRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let animateTapTurns: Bool
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> CoverCoordinator {
      CoverCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
      let configuration = WKWebViewConfiguration()
      configuration.registerEpubResourceSchemeHandler(context.coordinator.epubResourceSchemeHandler)
      let userContentController = WKUserContentController()
      userContentController.add(
        WeakWKScriptMessageHandler(delegate: context.coordinator),
        name: "readerBridge"
      )
      configuration.userContentController = userContentController

      let rootView = NSView(frame: .zero)
      rootView.wantsLayer = true
      rootView.layer?.masksToBounds = true

      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = context.coordinator
      webView.allowsBackForwardNavigationGestures = false
      webView.setValue(false, forKey: "drawsBackground")
      webView.allowsMagnification = true
      webView.underPageBackgroundColor = .clear
      webView.translatesAutoresizingMaskIntoConstraints = false
      webView.wantsLayer = true

      rootView.addSubview(webView)
      context.coordinator.bind(rootView: rootView, webView: webView)
      context.coordinator.update(from: self)
      return rootView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      context.coordinator.update(from: self)
    }
  }

  @MainActor
  final class CoverCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSGestureRecognizerDelegate {
    let epubResourceSchemeHandler = EpubResourceSchemeHandler()
    private enum NavigationDirection {
      case forward
      case backward
    }

    private struct TransitionRequest {
      let navigationID: UUID
      let direction: NavigationDirection
      let chapterIndex: Int
      let pageIndex: Int
      let rawPageIndex: Int
      let chapterURL: URL?
      let chapterMediaType: String?
      let rootURL: URL?
      let contentCSS: String
      let readiumProperties: [String: String?]
      let publicationLanguage: String?
      let publicationReadingProgression: WebPubReadingProgression?
      let chapterTitle: String?
      let totalProgression: Double?
      let shouldReload: Bool
      let appearanceChanged: Bool
      let theme: ReaderTheme
    }

    private enum Metrics {
      static let animationDuration: TimeInterval = 0.28
      static let movingShadowOpacity: Float = 0.12
      static let idleShadowOpacity: Float = 0.05
      static let movingShadowRadius: CGFloat = 5
      static let idleShadowRadius: CGFloat = 2
      static let movingShadowOffset: CGFloat = 3
      static let idleShadowOffset: CGFloat = 1
    }

    private var parent: WebPubPagedCoverView
    private weak var rootView: NSView?
    private weak var webView: WKWebView?
    private var webViewConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?
    private var infoOverlay: WebPubInfoOverlaySupport.AppKitOverlay?
    private weak var snapshotOverlayView: NSImageView?

    private var navigationID: UUID
    private var paginationNavigationID = UUID()
    private var renderedNavigationID = UUID()
    private var chapterIndex: Int = 0
    private var currentSubPageIndex: Int = 0
    private var totalPagesInChapter: Int = 1
    private var chapterURL: URL?
    private var chapterMediaType: String?
    private var rootURL: URL?
    private var contentCSS: String = ""
    private var readiumProperties: [String: String?] = [:]
    private var publicationLanguage: String?
    private var publicationReadingProgression: WebPubReadingProgression?
    private var paginationGeneration = 0
    private var detectedVerticalLayout = false
    private var isContentLoaded = false
    private var pendingDestination: EpubNavigationDestination?
    private var chapterTitle: String?
    private var totalProgression: Double?
    private var isAwaitingPaginationReady = false
    private var isAnimatingTransition = false
    private var pendingRefreshAfterTransition = false
    private var pendingTransition: TransitionRequest?
    private var snapshotRequestID: Int = 0
    private var horizontalAnimationOffset: CGFloat = 0

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: publicationLanguage,
        readingProgression: publicationReadingProgression,
        forceVertical: detectedVerticalLayout
      )
    }

    init(parent: WebPubPagedCoverView) {
      self.parent = parent
      navigationID = parent.viewModel.navigationID
      super.init()
    }

    func bind(rootView: NSView, webView: WKWebView) {
      self.rootView = rootView
      self.webView = webView
      installOverlayIfNeeded()
    }

    func update(from parent: WebPubPagedCoverView) {
      self.parent = parent
      guard let webView else { return }
      let navigationChanged =
        parent.viewModel.navigationRequest != nil
        && navigationID != parent.viewModel.navigationID

      let requestedChapterIndex = parent.viewModel.targetChapterIndex ?? parent.viewModel.currentChapterIndex
      let requestedRawPageIndex = parent.viewModel.targetPageIndex ?? parent.viewModel.currentPageIndex
      let requestedPageCount = parent.viewModel.chapterPageCount(at: requestedChapterIndex) ?? 1
      let requestedPageIndex =
        requestedRawPageIndex < 0
        ? max(0, requestedPageCount - 1)
        : max(0, requestedRawPageIndex)

      let requestedLocation = parent.viewModel.pageLocation(
        chapterIndex: requestedChapterIndex,
        pageIndex: requestedPageIndex
      )

      let theme = parent.preferences.resolvedTheme(for: parent.colorScheme)
      let fontPath = parent.preferences.fontFamily.fontName.flatMap {
        CustomFontStore.shared.getFontPath(for: $0)
      }
      let readiumPayload = parent.preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: parent.viewModel.resourceRootURL,
        viewportSize: parent.viewModel.resolvedViewportSize
      )

      let nextChapterURL = parent.viewModel.chapterURL(at: requestedChapterIndex)
      let nextChapterMediaType = parent.viewModel.chapterMediaType(at: requestedChapterIndex)
      let nextRootURL = parent.viewModel.resourceRootURL
      epubResourceSchemeHandler.configure(
        rootURL: nextRootURL,
        mediaTypesByRelativePath: parent.viewModel.mediaTypesByRelativePath
      )
      let shouldReload =
        nextChapterURL != chapterURL || nextChapterMediaType != chapterMediaType || nextRootURL != rootURL
      let appearanceChanged =
        contentCSS != readiumPayload.css
        || readiumProperties != readiumPayload.properties
        || publicationLanguage != parent.viewModel.publicationLanguage
        || publicationReadingProgression != parent.viewModel.publicationReadingProgression

      rootView?.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      webView.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor

      if isAnimatingTransition {
        pendingRefreshAfterTransition = true
        return
      }

      let hasPendingNavigation = navigationChanged
      let shouldAnimateNavigation =
        hasPendingNavigation
        && parent.animateTapTurns
        && parent.viewModel.navigationRequest?.destination.requiresFullExtent != true
        && isContentLoaded
        && (requestedChapterIndex != chapterIndex || requestedPageIndex != currentSubPageIndex)

      if shouldAnimateNavigation {
        let direction: NavigationDirection =
          requestedChapterIndex > chapterIndex
            || (requestedChapterIndex == chapterIndex && requestedPageIndex > currentSubPageIndex)
          ? .forward : .backward

        let request = TransitionRequest(
          navigationID: parent.viewModel.navigationID,
          direction: direction,
          chapterIndex: requestedChapterIndex,
          pageIndex: requestedPageIndex,
          rawPageIndex: requestedRawPageIndex,
          chapterURL: nextChapterURL,
          chapterMediaType: nextChapterMediaType,
          rootURL: nextRootURL,
          contentCSS: readiumPayload.css,
          readiumProperties: readiumPayload.properties,
          publicationLanguage: parent.viewModel.publicationLanguage,
          publicationReadingProgression: parent.viewModel.publicationReadingProgression,
          chapterTitle: requestedLocation?.title,
          totalProgression: requestedLocation.flatMap { location in
            parent.viewModel.totalProgression(location: location, chapterProgress: nil as Double?)
          },
          shouldReload: shouldReload,
          appearanceChanged: appearanceChanged,
          theme: theme
        )
        startAnimatedTransition(request)
        return
      }

      navigationID = parent.viewModel.navigationID
      applyRequestState(
        chapterIndex: requestedChapterIndex,
        pageIndex: requestedPageIndex,
        chapterURL: nextChapterURL,
        chapterMediaType: nextChapterMediaType,
        rootURL: nextRootURL,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: parent.viewModel.publicationLanguage,
        publicationReadingProgression: parent.viewModel.publicationReadingProgression,
        chapterTitle: requestedLocation?.title,
        totalProgression: requestedLocation.flatMap { location in
          parent.viewModel.totalProgression(location: location, chapterProgress: nil as Double?)
        }
      )

      pendingDestination = parent.viewModel.navigationRequest?.destination ?? .page(max(0, requestedPageIndex))

      applyTheme(theme)
      applyContentInsets()
      updateOverlayLabels()

      if shouldReload {
        loadContent(in: webView)
        return
      }

      if appearanceChanged || hasPendingNavigation {
        applyNavigation(on: webView, targetPageIndex: requestedPageIndex, appearanceChanged: appearanceChanged)
      }
    }

    private func startAnimatedTransition(_ request: TransitionRequest) {
      isAnimatingTransition = true
      pendingTransition = request
      captureCurrentSnapshot { [weak self] image in
        guard let self else { return }
        if let image {
          self.showSnapshotOverlay(image, theme: request.theme, direction: request.direction)
        }
        self.executeTransition(request)
      }
    }

    private func executeTransition(_ request: TransitionRequest) {
      navigationID = request.navigationID
      guard let webView else {
        finishAnimatedTransition(at: request.pageIndex)
        return
      }

      applyRequestState(
        chapterIndex: request.chapterIndex,
        pageIndex: request.pageIndex,
        chapterURL: request.chapterURL,
        chapterMediaType: request.chapterMediaType,
        rootURL: request.rootURL,
        contentCSS: request.contentCSS,
        readiumProperties: request.readiumProperties,
        publicationLanguage: request.publicationLanguage,
        publicationReadingProgression: request.publicationReadingProgression,
        chapterTitle: request.chapterTitle,
        totalProgression: request.totalProgression
      )
      applyTheme(request.theme)
      applyContentInsets()
      updateOverlayLabels()

      if request.direction == .backward {
        prepareIncomingPageForBackwardTransition()
      } else {
        resetWebViewPresentation()
      }

      if request.shouldReload {
        pendingDestination = request.rawPageIndex < 0 ? .lastPage : .page(request.pageIndex)
        loadContent(in: webView)
        return
      }

      pendingDestination = request.rawPageIndex < 0 ? .lastPage : .page(request.pageIndex)

      applyNavigation(on: webView, targetPageIndex: request.pageIndex, appearanceChanged: request.appearanceChanged)
    }

    private func captureCurrentSnapshot(completion: @escaping (NSImage?) -> Void) {
      guard let webView, isContentLoaded else {
        completion(nil)
        return
      }

      snapshotRequestID &+= 1
      let requestID = snapshotRequestID
      webView.takeSnapshot(with: nil) { [weak self] image, _ in
        Task { @MainActor in
          guard let self, self.snapshotRequestID == requestID else { return }
          completion(image)
        }
      }
    }

    private func showSnapshotOverlay(
      _ image: NSImage,
      theme: ReaderTheme,
      direction: NavigationDirection
    ) {
      guard let rootView, let webView else { return }
      removeSnapshotOverlay()

      let overlay = NSImageView(frame: webView.frame)
      overlay.image = image
      overlay.imageScaling = .scaleAxesIndependently
      overlay.alphaValue = 1.0
      overlay.wantsLayer = true
      overlay.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      overlay.layer?.masksToBounds = false
      overlay.layer?.shadowPath = CGPath(rect: overlay.bounds, transform: nil)
      if direction == .forward {
        applySnapshotShadow(to: overlay, direction: direction, isMoving: false)
        rootView.addSubview(overlay, positioned: .above, relativeTo: webView)
      } else {
        rootView.addSubview(overlay, positioned: .below, relativeTo: webView)
      }
      snapshotOverlayView = overlay
    }

    private func applySnapshotShadow(
      to overlay: NSImageView,
      direction: NavigationDirection,
      isMoving: Bool
    ) {
      overlay.layer?.shadowColor = NSColor.black.cgColor
      overlay.layer?.shadowOpacity = isMoving ? Metrics.movingShadowOpacity : Metrics.idleShadowOpacity
      overlay.layer?.shadowRadius = isMoving ? Metrics.movingShadowRadius : Metrics.idleShadowRadius
      overlay.layer?.shadowOffset = CGSize(
        width: isMoving
          ? (direction == .forward ? Metrics.movingShadowOffset : -Metrics.movingShadowOffset)
          : 0,
        height: Metrics.idleShadowOffset
      )
    }

    private func removeSnapshotOverlay() {
      snapshotOverlayView?.removeFromSuperview()
      snapshotOverlayView = nil
    }

    private func finishAnimatedTransition(at pageIndex: Int) {
      let direction = pendingTransition?.direction

      guard let direction else {
        removeSnapshotOverlay()
        resetWebViewPresentation()
        finalizeAnimatedTransition(at: pageIndex)
        return
      }

      switch direction {
      case .forward:
        guard let overlay = snapshotOverlayView else {
          removeSnapshotOverlay()
          resetWebViewPresentation()
          finalizeAnimatedTransition(at: pageIndex)
          return
        }

        let distance = overlay.frame.width
        let deltaX = coverEdgeOffset(distance: distance)
        applySnapshotShadow(to: overlay, direction: direction, isMoving: true)
        NSAnimationContext.runAnimationGroup { context in
          context.duration = Metrics.animationDuration
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          overlay.animator().setFrameOrigin(
            NSPoint(x: overlay.frame.origin.x + deltaX, y: overlay.frame.origin.y)
          )
        } completionHandler: { [weak self] in
          MainActor.assumeIsolated {
            self?.removeSnapshotOverlay()
            self?.resetWebViewPresentation()
            self?.finalizeAnimatedTransition(at: pageIndex)
          }
        }
      case .backward:
        animateIncomingPageCoverIn(pageIndex: pageIndex)
      }
    }

    private func finalizeAnimatedTransition(at pageIndex: Int) {
      pendingTransition = nil
      isAnimatingTransition = false
      commitPage(pageIndex)
      if pendingRefreshAfterTransition || navigationID != parent.viewModel.navigationID {
        pendingRefreshAfterTransition = false
        update(from: parent)
      }
    }

    private func applyRequestState(
      chapterIndex: Int,
      pageIndex: Int,
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      chapterTitle: String?,
      totalProgression: Double?
    ) {
      self.chapterIndex = chapterIndex
      self.currentSubPageIndex = pageIndex
      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.chapterTitle = chapterTitle
      self.totalProgression = totalProgression
    }

    private func loadContent(in webView: WKWebView) {
      guard let chapterURL, let rootURL else { return }
      isContentLoaded = false
      paginationGeneration += 1
      detectedVerticalLayout = false
      refreshDocumentStartUserScript(on: webView)
      totalPagesInChapter = 1
      isAwaitingPaginationReady = true
      webView.alphaValue = 0.01
      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    private func installOverlayIfNeeded() {
      guard let rootView, let webView, webViewConstraints == nil else { return }

      let insets = parent.viewModel.containerInsetsForLabels()
      let top = webView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: insets.top)
      let leading = webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
      let trailing = rootView.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
      let bottom = rootView.bottomAnchor.constraint(equalTo: webView.bottomAnchor, constant: insets.bottom)
      NSLayoutConstraint.activate([top, leading, trailing, bottom])
      webViewConstraints = (top, leading, trailing, bottom)
      infoOverlay = WebPubInfoOverlaySupport.AppKitOverlay(
        containerView: rootView,
        topOffset: parent.viewModel.labelTopOffset,
        bottomOffset: parent.viewModel.labelBottomOffset,
        theme: parent.preferences.resolvedTheme(for: parent.colorScheme)
      )
    }

    private func applyContentInsets() {
      let insets = parent.viewModel.containerInsetsForLabels()
      webViewConstraints?.top.constant = insets.top
      webViewConstraints?.bottom.constant = insets.bottom
      webViewConstraints?.leading.constant = insets.left + horizontalAnimationOffset
      webViewConstraints?.trailing.constant = insets.right - horizontalAnimationOffset
    }

    private func applyTheme(_ theme: ReaderTheme) {
      infoOverlay?.apply(theme: theme)
    }

    private func prepareIncomingPageForBackwardTransition() {
      guard let webView else { return }
      let distance = max(webView.bounds.width, rootView?.bounds.width ?? 0)
      guard distance > 0 else { return }
      horizontalAnimationOffset = coverEdgeOffset(distance: distance)
      applyContentInsets()
      webView.layer?.shadowPath = CGPath(rect: webView.bounds, transform: nil)
      applyWebViewShadow(isMoving: false)
      rootView?.layoutSubtreeIfNeeded()
    }

    private func animateIncomingPageCoverIn(pageIndex: Int) {
      guard let webView else {
        removeSnapshotOverlay()
        resetWebViewPresentation()
        finalizeAnimatedTransition(at: pageIndex)
        return
      }

      webView.alphaValue = 1
      webView.layer?.shadowPath = CGPath(rect: webView.bounds, transform: nil)
      applyWebViewShadow(isMoving: true)

      let insets = parent.viewModel.containerInsetsForLabels()
      horizontalAnimationOffset = 0

      NSAnimationContext.runAnimationGroup { context in
        context.duration = Metrics.animationDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        webViewConstraints?.leading.animator().constant = insets.left
        webViewConstraints?.trailing.animator().constant = insets.right
      } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          self?.removeSnapshotOverlay()
          self?.resetWebViewPresentation()
          self?.finalizeAnimatedTransition(at: pageIndex)
        }
      }
    }

    private func resetWebViewPresentation() {
      horizontalAnimationOffset = 0
      applyContentInsets()
      webView?.layer?.shadowOpacity = 0
      webView?.layer?.shadowRadius = 0
      webView?.layer?.shadowOffset = .zero
      webView?.layer?.shadowPath = nil
      rootView?.layoutSubtreeIfNeeded()
    }

    private func applyWebViewShadow(isMoving: Bool) {
      webView?.layer?.shadowColor = NSColor.black.cgColor
      webView?.layer?.shadowOpacity = isMoving ? Metrics.movingShadowOpacity : Metrics.idleShadowOpacity
      webView?.layer?.shadowRadius = isMoving ? Metrics.movingShadowRadius : Metrics.idleShadowRadius
      webView?.layer?.shadowOffset = CGSize(
        width: isMoving ? shadowXOffsetForMovingPage() : 0,
        height: Metrics.idleShadowOffset
      )
    }

    private func shadowXOffsetForMovingPage() -> CGFloat {
      coverEdgeOffset(distance: Metrics.movingShadowOffset) > 0
        ? -Metrics.movingShadowOffset : Metrics.movingShadowOffset
    }

    private func coverEdgeOffset(distance: CGFloat) -> CGFloat {
      paginationLayout.reversesHorizontalGestureDirection ? distance : -distance
    }

    private func updateProgressDisplay(for pageIndex: Int) {
      let location = parent.viewModel.pageLocation(
        chapterIndex: chapterIndex,
        pageIndex: pageIndex
      )
      chapterTitle = location?.title
      totalProgression = location.flatMap { location in
        parent.viewModel.totalProgression(location: location, chapterProgress: nil)
      }
    }

    private func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .paged,
        bookTitle: parent.bookTitle,
        chapterTitle: chapterTitle,
        totalProgression: totalProgression,
        currentPageIndex: currentSubPageIndex,
        totalPagesInChapter: totalPagesInChapter,
        showingControls: parent.showingControls,
        isRTL: publicationReadingProgression == .rtl,
        overlayPreferences: parent.overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    private func applyNavigation(on webView: WKWebView, targetPageIndex: Int, appearanceChanged: Bool) {
      guard isContentLoaded else { return }
      if appearanceChanged || isAwaitingPaginationReady || pendingDestination == .lastPage
        || parent.viewModel.navigationRequiresFullExtent(for: chapterIndex)
      {
        applyPagination(on: webView, targetPageIndex: targetPageIndex)
        return
      }

      let requestID = navigationID
      let generation = paginationGeneration
      let js = WebPubPagedJavaScriptBuilder.makeScrollToPageAndSettleScript(
        pageIndex: targetPageIndex, paginationLayout: paginationLayout
      )
      webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
        Task { @MainActor in
          guard let self, self.navigationID == requestID, self.paginationGeneration == generation else { return }
          guard case .success(let value) = result, let metrics = value as? [String: Any],
            let total = metrics["totalPages"] as? Int, let page = metrics["currentPage"] as? Int
          else {
            self.applyPagination(on: webView, targetPageIndex: targetPageIndex)
            return
          }
          self.totalPagesInChapter = max(1, total)
          self.paginationNavigationID = requestID
          self.renderedNavigationID = requestID
          self.pendingDestination = nil
          if requestID == self.parent.viewModel.navigationID {
            self.parent.viewModel.updateChapterPageCount(self.totalPagesInChapter, for: self.chapterIndex)
          }
          if self.pendingTransition != nil {
            self.finishAnimatedTransition(at: page)
          } else {
            self.commitPage(page)
          }
        }
      }
    }

    private func applyPagination(on webView: WKWebView, targetPageIndex: Int) {
      guard isContentLoaded else { return }
      if isAwaitingPaginationReady, webView.alphaValue > 0.1 {
        webView.alphaValue = 0.01
      }
      isAwaitingPaginationReady = true
      paginationGeneration += 1
      let generation = paginationGeneration
      paginationNavigationID = navigationID
      injectCSS(on: webView) { [weak self] in
        guard let self, generation == paginationGeneration else { return }
        self.injectPaginationJS(
          on: webView,
          targetPageIndex: targetPageIndex,
          preferLastPage: self.pendingDestination == .lastPage
        )
      }
    }

    private func commitPage(_ pageIndex: Int, resolvedAnchor: String? = nil) {
      currentSubPageIndex = max(0, pageIndex)
      updateProgressDisplay(for: currentSubPageIndex)
      parent.viewModel.commitPosition(
        EpubPageLanding(
          chapterIndex: chapterIndex, pageIndex: currentSubPageIndex,
          layout: .content(pageCount: totalPagesInChapter), navigationID: renderedNavigationID,
          resolvedAnchor: resolvedAnchor
        ))
      updateOverlayLabels()
    }

    private func scrollToPage(_ pageIndex: Int, animated: Bool) {
      guard let webView else { return }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToPageScript(
        pageIndex: pageIndex,
        animated: animated,
        paginationLayout: paginationLayout
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Lands on an in-chapter anchor (footnote, cross-reference) and reports
    /// the resolved page index, or nil when the anchor does not exist.
    private func scrollToAnchor(
      _ anchor: String, on webView: WKWebView, completion: @escaping (Int?) -> Void
    ) {
      guard isContentLoaded else {
        completion(nil)
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToAnchorScript(
        anchor: anchor,
        paginationLayout: paginationLayout
      )
      let requestID = navigationID
      webView.evaluateJavaScript(js) { [weak self] result, _ in
        Task { @MainActor in
          guard let self, self.navigationID == requestID, self.parent.viewModel.navigationID == requestID else {
            return
          }
          completion(result as? Int)
        }
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(
        on: webView,
        targetPageIndex: pendingDestination?.estimatedPageIndex(pageCount: totalPagesInChapter) ?? currentSubPageIndex)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      guard navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url
      else {
        decisionHandler(.allow)
        return
      }

      parent.viewModel.navigateToURL(url)
      decisionHandler(.cancel)
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let body = message.body as? [String: Any],
        let type = body["type"] as? String
      else { return }
      guard paginationNavigationID == navigationID else { return }
      if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
      if type == "writingModeMismatch" {
        guard !detectedVerticalLayout, let webView else { return }
        detectedVerticalLayout = true
        applyPagination(on: webView, targetPageIndex: currentSubPageIndex)
        return
      }
      guard type == "ready" || type == "pageCountUpdate" else { return }
      renderedNavigationID = paginationNavigationID

      if let total = body["totalPages"] as? Int {
        totalPagesInChapter = max(1, total)
        if navigationID == parent.viewModel.navigationID {
          parent.viewModel.updateChapterPageCount(totalPagesInChapter, for: chapterIndex)
        }
      }

      let actualPage = max(0, body["currentPage"] as? Int ?? currentSubPageIndex)

      if type == "pageCountUpdate" {
        commitPage(min(actualPage, totalPagesInChapter - 1))
        return
      }

      pendingDestination = nil
      isAwaitingPaginationReady = false
      webView?.alphaValue = 1
      updateProgressDisplay(for: actualPage)
      updateOverlayLabels()

      if pendingTransition != nil {
        finishAnimatedTransition(at: actualPage)
      } else {
        commitPage(actualPage)
      }

      // Fragment navigation lands after the target chapter has paginated.
      if let webView, let anchor = parent.viewModel.pendingAnchorNavigation(for: chapterIndex) {
        scrollToAnchor(anchor.anchor, on: webView) { [weak self] resolvedPage in
          guard let self, navigationID == anchor.id, parent.viewModel.navigationID == anchor.id else { return }
          let page = resolvedPage ?? 0
          if resolvedPage == nil { scrollToPage(0, animated: false) }
          commitPage(page, resolvedAnchor: anchor.anchor)
        }
      }
    }

    private func injectPaginationJS(
      on webView: WKWebView,
      targetPageIndex: Int,
      preferLastPage: Bool
    ) {
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: pendingDestination?.estimatedPageIndex(pageCount: totalPagesInChapter) ?? targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout,
        generation: paginationGeneration,
        requiresFullExtent: pendingDestination?.progression != nil
          || parent.viewModel.navigationRequiresFullExtent(for: chapterIndex),
        targetProgression: pendingDestination?.progression
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func refreshDocumentStartUserScript(on webView: WKWebView) {
      let controller = webView.configuration.userContentController
      controller.removeAllUserScripts()
      let script = WebPubThemeJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func injectCSS(on webView: WKWebView, completion: (() -> Void)? = nil) {
      let js = WebPubThemeJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      webView.evaluateJavaScript(js) { _, _ in
        completion?()
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
      true
    }
  }
#endif
