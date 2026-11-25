#if os(macOS)
  import AppKit
  import SwiftUI
  import WebKit

  struct WebPubScrolledView: NSViewRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let tapScrollPercentage: Double
    let animateTapTurns: Bool
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
      let configuration = WKWebViewConfiguration()
      configuration.registerEpubResourceSchemeHandler(context.coordinator.epubResourceSchemeHandler)
      let userContentController = WKUserContentController()
      userContentController.add(WeakWKScriptMessageHandler(delegate: context.coordinator), name: "readerBridge")
      configuration.userContentController = userContentController

      let rootView = NSView(frame: .zero)
      rootView.wantsLayer = true

      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = context.coordinator
      webView.allowsBackForwardNavigationGestures = false
      webView.setValue(false, forKey: "drawsBackground")
      webView.allowsMagnification = true
      webView.underPageBackgroundColor = .clear
      webView.translatesAutoresizingMaskIntoConstraints = false

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
  final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSGestureRecognizerDelegate {
    let epubResourceSchemeHandler = EpubResourceSchemeHandler()
    private var parent: WebPubScrolledView
    private weak var rootView: NSView?
    private weak var webView: WKWebView?
    private var webViewConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?
    private var infoOverlay: WebPubInfoOverlaySupport.AppKitOverlay?

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
    private var isContentLoaded = false
    private var pendingDestination: EpubNavigationDestination?
    private var readyToken: Int = 0
    private var lastKnownDocumentScrollTop: CGFloat = 0
    private var lastKnownDocumentContentHeight: CGFloat = 0
    private var lastKnownDocumentViewportHeight: CGFloat = 0
    private var chapterTitle: String?
    private var totalProgression: Double?
    private var animateTapTurns = true

    init(parent: WebPubScrolledView) {
      self.parent = parent
      navigationID = parent.viewModel.navigationID
      super.init()
    }

    func bind(rootView: NSView, webView: WKWebView) {
      self.rootView = rootView
      self.webView = webView
      installOverlayIfNeeded()
    }

    func update(from parent: WebPubScrolledView) {
      self.parent = parent
      guard let webView else { return }
      let navigationChanged =
        parent.viewModel.navigationRequest != nil
        && navigationID != parent.viewModel.navigationID

      let selectedChapterIndex = parent.viewModel.targetChapterIndex ?? parent.viewModel.currentChapterIndex
      let selectedPageIndex = parent.viewModel.targetPageIndex ?? parent.viewModel.currentPageIndex
      let currentLocation = parent.viewModel.pageLocation(
        chapterIndex: selectedChapterIndex,
        pageIndex: max(0, selectedPageIndex)
      )

      let theme = parent.preferences.resolvedTheme(for: parent.colorScheme)
      let fontPath = parent.preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = parent.preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        flowStyle: .scrolled,
        rootURL: parent.viewModel.resourceRootURL,
        viewportSize: parent.viewModel.resolvedViewportSize
      )

      let nextChapterURL = parent.viewModel.chapterURL(at: selectedChapterIndex)
      let nextChapterMediaType = parent.viewModel.chapterMediaType(at: selectedChapterIndex)
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
        || animateTapTurns != parent.animateTapTurns

      navigationID = parent.viewModel.navigationID
      chapterIndex = selectedChapterIndex
      chapterURL = nextChapterURL
      chapterMediaType = nextChapterMediaType
      rootURL = nextRootURL
      contentCSS = readiumPayload.css
      readiumProperties = readiumPayload.properties
      publicationLanguage = parent.viewModel.publicationLanguage
      publicationReadingProgression = parent.viewModel.publicationReadingProgression
      chapterTitle = currentLocation?.title
      animateTapTurns = parent.animateTapTurns
      totalProgression = currentLocation.flatMap { location in
        parent.viewModel.totalProgression(location: location, chapterProgress: nil)
      }

      pendingDestination = parent.viewModel.navigationRequest?.destination ?? .page(max(0, selectedPageIndex))

      if shouldReload {
        loadContent(in: webView)
        return
      }

      rootView?.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      webView.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      applyTheme(theme)
      applyContentInsets()
      updateOverlayLabels()

      if appearanceChanged || navigationChanged {
        applyPagination(on: webView, targetPageIndex: max(0, selectedPageIndex))
      } else if let currentLocation {
        updateViewModelLocation(from: currentLocation.pageIndex)
      }
    }

    private func loadContent(in webView: WKWebView) {
      guard let chapterURL, let rootURL else { return }
      isContentLoaded = false
      readyToken += 1
      lastKnownDocumentScrollTop = 0
      lastKnownDocumentContentHeight = 0
      lastKnownDocumentViewportHeight = 0
      totalPagesInChapter = 1
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
      webViewConstraints?.leading.constant = insets.left
      webViewConstraints?.trailing.constant = insets.right
    }

    private func applyTheme(_ theme: ReaderTheme) {
      infoOverlay?.apply(theme: theme)
    }

    private func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .scrolled,
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
      readyToken += 1
      let token = readyToken
      paginationNavigationID = navigationID
      injectCSS(on: webView) { [weak self] in
        guard let self, token == readyToken else { return }
        self.injectPaginationJS(
          on: webView,
          targetPageIndex: targetPageIndex,
          preferLastPage: self.pendingDestination == .lastPage,
          token: token
        )
      }
    }

    private func scrollToPreviousPage() {
      guard chapterIndex >= 0 else { return }
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }
      let currentOffset = lastKnownDocumentScrollTop
      if currentOffset <= 1 {
        if chapterIndex > 0 {
          parent.viewModel.navigateToPage(chapterIndex: chapterIndex - 1, pageIndex: -1)
        }
        return
      }
      let step = pageHeight * CGFloat(parent.tapScrollPercentage / 100.0)
      scrollDocument(to: max(0, currentOffset - step))
    }

    private func scrollToNextPage() {
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }
      let maxOffset = max(0, effectiveContentHeight - pageHeight)
      let currentOffset = lastKnownDocumentScrollTop
      if currentOffset >= maxOffset - 1 {
        if chapterIndex < max(0, parent.viewModel.chapterCount - 1) {
          parent.viewModel.navigateToPage(chapterIndex: chapterIndex + 1, pageIndex: 0)
        } else {
          parent.onEndReached()
        }
        return
      }
      let step = pageHeight * CGFloat(parent.tapScrollPercentage / 100.0)
      scrollDocument(to: min(maxOffset, currentOffset + step))
    }

    private func scrollDocument(to targetOffset: CGFloat, animated: Bool = true) {
      guard let webView else { return }
      let clampedOffset = max(0, targetOffset)
      lastKnownDocumentScrollTop = clampedOffset
      let offset = Double(clampedOffset)
      let duration = animated && animateTapTurns ? 0.3 : 0
      let js = WebPubPagedJavaScriptBuilder.makeScrollDocumentScript(
        targetOffset: offset, duration: duration, token: readyToken
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Lands on an in-chapter anchor (footnote, cross-reference). The
    /// resulting scroll position flows back through the scroll metrics
    /// messages, so no page commit is needed here. The completion reports
    /// whether the anchor exists.
    private func scrollToAnchor(
      _ anchor: String, on webView: WKWebView, completion: @escaping (Bool) -> Void
    ) {
      guard isContentLoaded else {
        completion(false)
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToDocumentAnchorScript(anchor: anchor)
      let requestID = navigationID
      webView.evaluateJavaScript(js) { [weak self] result, _ in
        Task { @MainActor in
          guard let self, self.navigationID == requestID, self.parent.viewModel.navigationID == requestID else {
            return
          }
          completion((result as? Bool) ?? false)
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
      guard let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }
      guard paginationNavigationID == navigationID, navigationID == parent.viewModel.navigationID else { return }
      if let token = body["token"] as? Int, token != readyToken {
        return
      }

      updateDocumentMetrics(from: body)

      if let total = body["totalPages"] as? Int {
        let normalizedTotal = max(1, total)
        totalPagesInChapter = normalizedTotal
        if navigationID == parent.viewModel.navigationID {
          parent.viewModel.updateChapterPageCount(normalizedTotal, for: chapterIndex)
        }
      }

      let actualPage = max(
        0,
        min(totalPagesInChapter - 1, body["currentPage"] as? Int ?? currentSubPageIndex)
      )

      if type == "ready" {
        renderedNavigationID = paginationNavigationID
        pendingDestination = nil
        currentSubPageIndex = actualPage

        // A cross-chapter link with a fragment lands here once the target
        // chapter has laid out.
        if let webView, let anchor = parent.viewModel.pendingAnchorNavigation(for: chapterIndex) {
          scrollToAnchor(anchor.anchor, on: webView) { [weak self] found in
            guard let self, navigationID == anchor.id, parent.viewModel.navigationID == anchor.id else { return }
            if !found { scrollDocument(to: 0, animated: false) }
            let requestID = navigationID
            webView.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
              guard let self, self.navigationID == requestID, self.parent.viewModel.navigationID == requestID else {
                return
              }
              let offset = (result as? Double) ?? 0
              currentSubPageIndex = scrollPagination.pageIndex(at: CGFloat(offset))
              updateViewModelLocation(from: currentSubPageIndex, resolvedAnchor: anchor.anchor)
            }
          }
        }
      } else if currentSubPageIndex != actualPage {
        currentSubPageIndex = actualPage
      }

      updateViewModelLocation(from: currentSubPageIndex)
    }

    private func updateViewModelLocation(from pageIndex: Int, resolvedAnchor: String? = nil) {
      let normalizedPageIndex = max(0, pageIndex)
      parent.viewModel.commitPosition(
        EpubPageLanding(
          chapterIndex: chapterIndex, pageIndex: normalizedPageIndex,
          layout: .content(pageCount: totalPagesInChapter), navigationID: renderedNavigationID,
          resolvedAnchor: resolvedAnchor
        ))
      updateOverlayLabels()
    }

    private func updateDocumentMetrics(from body: [String: Any]) {
      if let contentHeight = body["contentHeight"] as? Double, contentHeight > 0 {
        lastKnownDocumentContentHeight = CGFloat(contentHeight)
      }
      if let viewportHeight = body["viewportHeight"] as? Double, viewportHeight > 0 {
        lastKnownDocumentViewportHeight = CGFloat(viewportHeight)
      }
      if let scrollTop = body["scrollTop"] as? Double, scrollTop >= 0 {
        lastKnownDocumentScrollTop = CGFloat(scrollTop)
      }
    }

    private var scrollPagination: EpubScrollPagination {
      EpubScrollPagination(contentHeight: effectiveContentHeight, viewportHeight: effectiveViewportHeight)
    }

    private var effectiveViewportHeight: CGFloat {
      max(1, lastKnownDocumentViewportHeight)
    }

    private var effectiveContentHeight: CGFloat {
      max(lastKnownDocumentContentHeight, effectiveViewportHeight)
    }

    private func injectPaginationJS(on webView: WKWebView, targetPageIndex: Int, preferLastPage: Bool, token: Int) {
      let js = WebPubPagedJavaScriptBuilder.makeScrolledPaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        token: token,
        requiresFullExtent: pendingDestination?.progression != nil
          || parent.viewModel.navigationRequiresFullExtent(for: chapterIndex),
        waitForStableLayout: false,
        targetProgression: pendingDestination?.progression
      )

      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectCSS(on webView: WKWebView, completion: (() -> Void)? = nil) {
      let js = WebPubThemeJavaScriptBuilder.makeInjectCSSScript(
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
