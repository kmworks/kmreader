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
    private var isContentLoaded = false
    private var pendingPageIndex: Int?
    private var pendingJumpToLastPage: Bool = false
    private var targetProgressionOnReady: Double?
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
        readingProgression: publicationReadingProgression
      )
    }

    init(parent: WebPubPagedCoverView) {
      self.parent = parent
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

      let requestedChapterIndex = parent.viewModel.targetChapterIndex ?? parent.viewModel.currentChapterIndex
      let requestedRawPageIndex = parent.viewModel.targetPageIndex ?? parent.viewModel.currentPageIndex
      let requestedPageCount = parent.viewModel.chapterPageCount(at: requestedChapterIndex) ?? 1
      let requestedPageIndex =
        requestedRawPageIndex < 0
        ? max(0, requestedPageCount - 1)
        : max(0, min(requestedRawPageIndex, requestedPageCount - 1))

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

      let hasPendingNavigation =
        parent.viewModel.targetChapterIndex != nil || parent.viewModel.targetPageIndex != nil
      let shouldAnimateNavigation =
        hasPendingNavigation
        && parent.animateTapTurns
        && isContentLoaded
        && (requestedChapterIndex != chapterIndex || requestedPageIndex != currentSubPageIndex)

      if shouldAnimateNavigation {
        let direction: NavigationDirection =
          requestedChapterIndex > chapterIndex
            || (requestedChapterIndex == chapterIndex && requestedPageIndex > currentSubPageIndex)
          ? .forward : .backward

        let request = TransitionRequest(
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

      if let targetChapterIndex = parent.viewModel.targetChapterIndex,
        let targetPageIndex = parent.viewModel.targetPageIndex,
        targetChapterIndex == chapterIndex
      {
        pendingPageIndex = max(0, targetPageIndex)
        pendingJumpToLastPage = targetPageIndex < 0
      } else {
        pendingPageIndex = requestedPageIndex
        pendingJumpToLastPage = false
      }

      applyTheme(theme)
      applyContentInsets()
      updateOverlayLabels()

      if shouldReload {
        targetProgressionOnReady = parent.viewModel.initialProgression(for: requestedChapterIndex)
        loadContent(in: webView)
        return
      }

      if appearanceChanged || hasPendingNavigation {
        applyPagination(on: webView, targetPageIndex: requestedPageIndex)
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
        pendingPageIndex = max(0, request.rawPageIndex)
        pendingJumpToLastPage = request.rawPageIndex < 0
        targetProgressionOnReady = parent.viewModel.initialProgression(for: request.chapterIndex)
        loadContent(in: webView)
        return
      }

      pendingPageIndex = request.pageIndex
      pendingJumpToLastPage = false
      targetProgressionOnReady = nil

      if request.appearanceChanged {
        applyPagination(on: webView, targetPageIndex: request.pageIndex)
        return
      }

      scrollToPage(request.pageIndex, animated: false)
      finishAnimatedTransition(at: request.pageIndex)
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
      if pendingRefreshAfterTransition {
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

    private func applyPagination(on webView: WKWebView, targetPageIndex: Int) {
      guard isContentLoaded else { return }
      if isAwaitingPaginationReady, webView.alphaValue > 0.1 {
        webView.alphaValue = 0.01
      }
      injectCSS(on: webView) { [weak self] in
        self?.injectPaginationJS(
          on: webView,
          targetPageIndex: targetPageIndex,
          preferLastPage: self?.pendingJumpToLastPage ?? false
        )
      }
    }

    private func commitPage(_ pageIndex: Int) {
      currentSubPageIndex = max(0, pageIndex)
      updateProgressDisplay(for: currentSubPageIndex)
      parent.viewModel.currentChapterIndex = chapterIndex
      parent.viewModel.currentPageIndex = currentSubPageIndex
      parent.viewModel.targetChapterIndex = nil
      parent.viewModel.targetPageIndex = nil
      parent.viewModel.pageDidChange()
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(on: webView, targetPageIndex: pendingPageIndex ?? currentSubPageIndex)
      pendingPageIndex = nil
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

      if let chapterURL, url.deletingFragment == chapterURL.deletingFragment {
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
        let type = body["type"] as? String,
        type == "ready"
      else { return }

      if let total = body["totalPages"] as? Int {
        totalPagesInChapter = max(1, total)
        parent.viewModel.updateChapterPageCount(totalPagesInChapter, for: chapterIndex)
      }

      var actualPage = max(0, body["currentPage"] as? Int ?? currentSubPageIndex)

      if pendingJumpToLastPage {
        pendingJumpToLastPage = false
      } else if let progression = targetProgressionOnReady {
        let targetIndex = max(
          0,
          min(totalPagesInChapter - 1, Int(floor(Double(totalPagesInChapter) * progression)))
        )
        if targetIndex != actualPage {
          actualPage = targetIndex
          scrollToPage(targetIndex, animated: false)
        }
        targetProgressionOnReady = nil
      }

      isAwaitingPaginationReady = false
      webView?.alphaValue = 1
      updateProgressDisplay(for: actualPage)
      updateOverlayLabels()

      if pendingTransition != nil {
        finishAnimatedTransition(at: actualPage)
      } else {
        commitPage(actualPage)
      }
    }

    private func injectPaginationJS(
      on webView: WKWebView,
      targetPageIndex: Int,
      preferLastPage: Bool
    ) {
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectCSS(on webView: WKWebView, completion: (() -> Void)? = nil) {
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
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
