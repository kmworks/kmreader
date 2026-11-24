#if os(iOS)
  import UIKit
  import WebKit

  @MainActor
  final class WebViewEpubPageRenderer: NSObject, EpubPageRenderer, WKNavigationDelegate, WKScriptMessageHandler {
    private weak var host: EpubPageViewController?
    private var configuration: EpubChapterConfiguration
    private var webView: WKWebView!
    private let epubResourceSchemeHandler = EpubResourceSchemeHandler()
    private var paginationGeneration = 0
    private var paginationNavigationID = UUID()
    // Set when the content probe reports a publisher-declared vertical writing
    // mode that the manifest metadata did not advertise.
    private var detectedVerticalLayout = false
    private(set) var isContentLoaded = false

    var contentView: UIView { webView }
    let refreshesWhenAppearingWithSameGeometry = false
    let reloadsOnAppearanceChange = false
    let forcesReloadWhenEnsured = true

    init(host: EpubPageViewController, configuration: EpubChapterConfiguration) {
      self.host = host
      self.configuration = configuration
      super.init()
    }

    func install(in container: UIView) {
      let config = WKWebViewConfiguration()
      epubResourceSchemeHandler.configure(
        rootURL: configuration.rootURL,
        mediaTypesByRelativePath: configuration.mediaTypesByRelativePath
      )
      config.registerEpubResourceSchemeHandler(epubResourceSchemeHandler)
      config.defaultWebpagePreferences.preferredContentMode = .mobile
      let controller = WKUserContentController()
      // Use weak wrapper to avoid retain cycle (WKUserContentController retains handlers strongly)
      controller.add(WeakWKScriptMessageHandler(delegate: self), name: "readerBridge")
      config.userContentController = controller

      webView = WKWebView(frame: .zero, configuration: config)
      refreshDocumentStartUserScript()
      webView.navigationDelegate = self
      webView.scrollView.isScrollEnabled = false
      webView.scrollView.bounces = false
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.showsVerticalScrollIndicator = false
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.isOpaque = false
      webView.alpha = 0
      applyTheme(configuration.theme)

      container.addSubview(webView)
      webView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        webView.topAnchor.constraint(equalTo: container.topAnchor),
        webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }

    func configure(_ configuration: EpubChapterConfiguration) {
      self.configuration = configuration
      if webView != nil {
        epubResourceSchemeHandler.configure(
          rootURL: configuration.rootURL,
          mediaTypesByRelativePath: configuration.mediaTypesByRelativePath
        )
        // The document-start script snapshots the theme; keep it current so
        // the next chapter load paints with the right styles immediately.
        refreshDocumentStartUserScript()
      }
    }

    // Applies the theme CSS at document start (instead of waiting for the
    // didFinish evaluateJavaScript round-trip) to shorten the first-chapter
    // white window. The didFinish injection stays as the idempotent fallback.
    private func refreshDocumentStartUserScript() {
      guard let controller = webView?.configuration.userContentController else { return }
      controller.removeAllUserScripts()
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: configuration.contentCSS,
        readiumProperties: configuration.readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: configuration.publicationLanguage,
        readingProgression: configuration.publicationReadingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      controller.addUserScript(
        WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      )
    }

    func applyTheme(_ theme: ReaderTheme) {
      guard webView != nil else { return }
      webView.backgroundColor = theme.uiColorBackground
      webView.scrollView.backgroundColor = .clear
    }

    func loadIfNeeded(force: Bool) {
      guard let host, let chapterURL = configuration.chapterURL, let rootURL = configuration.rootURL else { return }

      // The web view loads the chapter through the resource scheme, so the raw
      // chapter URL never matches; compare the rewritten scheme URL instead.
      let chapterSchemeURL = EpubResourceScheme.url(for: chapterURL, rootURL: rootURL)
      let urlMatches =
        chapterSchemeURL != nil && webView.url?.deletingFragment == chapterSchemeURL

      // If URL matches and content is loaded, just update pagination.
      // We don't hide the webview or show the loader here to avoid flickering
      // when just transitioning within the same chapter.
      if urlMatches && isContentLoaded {
        applyPagination(scrollToPage: host.currentSubPageIndex)
        return
      }

      // Skip reload if URL matches and not forcing
      if !force && urlMatches { return }

      // New content loading - show indicator and keep webview active but hidden
      isContentLoaded = false
      detectedVerticalLayout = false
      paginationGeneration += 1
      refreshDocumentStartUserScript()
      host.rendererPrepareForReload()

      // Use a near-zero alpha instead of exactly 0.
      // WebKit sometimes throttles layout/JS execution for elements with alpha=0.
      webView.alpha = 0.01

      // Only show loading indicator if WebView has valid size (is visible)
      // For pre-loaded pages with 0x0 size, don't show indicator
      let webViewSize = webView.bounds.size
      if webViewSize.width > 0 && webViewSize.height > 0 {
        host.rendererStartLoading()
      }

      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    func applyPagination(scrollToPage pageIndex: Int) {
      guard isContentLoaded else { return }
      let size = webView.bounds.size
      guard size.width > 0, size.height > 0 else { return }

      // Use a near-zero alpha to indicate transition if not already showing.
      // This prevents WebKit from throttling layout while keeping the view hidden from users.
      if webView.alpha < 0.1 {
        webView.alpha = 0.01
        host?.rendererStartLoading()
      }

      paginationGeneration += 1
      let generation = paginationGeneration
      paginationNavigationID = host?.navigationID ?? UUID()
      injectCSS { [weak self] in
        guard let self, generation == paginationGeneration else { return }
        self.injectPaginationJS(
          targetPageIndex: pageIndex,
          preferLastPage: self.host?.preferLastPageOnReady ?? false
        )
      }
    }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: configuration.publicationLanguage,
        readingProgression: configuration.publicationReadingProgression,
        forceVertical: detectedVerticalLayout
      )
    }

    private func injectCSS(completion: (() -> Void)? = nil) {
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: configuration.contentCSS,
        readiumProperties: configuration.readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: configuration.publicationLanguage,
        readingProgression: configuration.publicationReadingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      webView.evaluateJavaScript(js) { _, _ in
        completion?()
      }
    }

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool) {
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout,
        generation: paginationGeneration,
        requiresFullExtent: host?.targetProgressionOnReady != nil
          || host?.requiresFullExtentProvider?(configuration.chapterIndex) == true
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func scrollToPage(_ pageIndex: Int, completion: (() -> Void)?) {
      guard isContentLoaded else {
        completion?()
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToPageScript(
        pageIndex: pageIndex,
        animated: false,
        paginationLayout: paginationLayout
      )
      webView.evaluateJavaScript(js) { _, _ in completion?() }
    }

    func scrollToPageAndSettle(_ pageIndex: Int, completion: @escaping () -> Void) {
      guard isContentLoaded else {
        host?.rendererSetPendingPageIndex(pageIndex)
        completion()
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToPageAndSettleScript(
        pageIndex: pageIndex,
        paginationLayout: paginationLayout
      )
      webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { _ in
        Task { @MainActor in
          completion()
        }
      }
    }

    // Jumps to an in-chapter anchor (footnote, endnote, cross-reference) and
    // lands on the page containing it. The completion reports the resolved
    // page index, or nil when the anchor does not exist.
    func scrollToAnchor(_ anchor: String, completion: @escaping (Int?) -> Void) {
      guard isContentLoaded else {
        completion(nil)
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToAnchorScript(
        anchor: anchor,
        paginationLayout: paginationLayout
      )
      let requestID = host?.navigationID
      webView.evaluateJavaScript(js) { [weak host] result, _ in
        Task { @MainActor in
          guard let host, let requestID, host.acceptsNavigation(requestID) else { return }
          completion(result as? Int)
        }
      }
    }

    func handleLinkTap(at point: CGPoint, in hostView: UIView) -> Bool {
      false
    }

    func prepareForSnapshot() {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard let host else { return }
      isContentLoaded = true
      applyPagination(scrollToPage: host.rendererPendingOrCurrentPageIndex())
      host.rendererConsumePendingPageIndex()
      // Visibility is handled in userContentController when pagination is ready
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      preferences: WKWebpagePreferences,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
      preferences.preferredContentMode = .mobile

      // Allow initial page load
      guard let url = navigationAction.request.url else {
        decisionHandler(.allow, preferences)
        return
      }

      // Allow file:// URLs for the same domain (CSS, images, etc.)
      if navigationAction.navigationType == .other {
        decisionHandler(.allow, preferences)
        return
      }

      // Handle link clicks
      if navigationAction.navigationType == .linkActivated {
        let isInBookLink =
          url.scheme == EpubResourceScheme.scheme
          || url.scheme == "file"
          || url.scheme == nil
        if isInBookLink {
          // Same-chapter anchors (footnotes, cross-references) scroll in
          // place; a full navigation would land on page 0 of the chapter.
          if let fragment = url.fragment, !fragment.isEmpty, isCurrentChapterURL(url) {
            let originPage = host?.currentSubPageIndex ?? 0
            scrollToAnchor(fragment) { [weak host] page in
              guard let host else { return }
              // Commit the resolved page so native navigation and progress
              // reporting follow the jumped-to page; cover and curl
              // controllers never see a scroll event for this programmatic
              // move.
              if let page {
                host.commitAnchorLanding(page: page, originPage: originPage)
              } else {
                host.onLinkTap?(url)
              }
            }
            decisionHandler(.cancel, preferences)
            return
          }
          host?.onLinkTap?(url)
          decisionHandler(.cancel, preferences)
          return
        }
        // For external links, could open in Safari later
        decisionHandler(.cancel, preferences)
        return
      }

      decisionHandler(.allow, preferences)
    }

    private func isCurrentChapterURL(_ url: URL) -> Bool {
      guard let chapterURL = configuration.chapterURL else { return false }
      let base = url.deletingFragment
      if let rootURL = configuration.rootURL,
        let chapterSchemeURL = EpubResourceScheme.url(for: chapterURL, rootURL: rootURL),
        base == chapterSchemeURL.deletingFragment
      {
        return true
      }
      return base.standardizedFileURL.path == chapterURL.standardizedFileURL.path
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let host, let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }
      guard paginationNavigationID == host.navigationID else { return }

      if type == "ready" {
        // A superseded pagination pass must not resurrect stale counts or positions.
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          var actualPage = body["currentPage"] as? Int ?? host.currentSubPageIndex

          host.rendererDidProducePageCount(normalizedTotal, navigationID: paginationNavigationID)

          // Handle target progression jump if requested (e.g. on initial book open).
          // We ignore this if preferLastPageOnReady is true, as that takes precedence.
          if let progression = host.targetProgressionOnReady, !host.preferLastPageOnReady {
            let targetIndex = max(0, min(normalizedTotal - 1, Int(floor(Double(normalizedTotal) * progression))))
            if targetIndex != actualPage {
              actualPage = targetIndex
              scrollToPage(targetIndex, completion: nil)
            }
            host.targetProgressionOnReady = nil
          }

          // Sync the current sub-page index with the actual page landed on by JS or progression calculation.
          host.currentSubPageIndex = actualPage
          host.rendererDidAdjustPageIndex(actualPage, navigationID: paginationNavigationID)

          host.preferLastPageOnReady = false
          host.updateOverlayLabels()
        }

        // Stop the loading indicator and finally show the WebView content.
        host.rendererStopLoading()
        webView.alpha = 1
        // A cross-chapter link with a fragment lands here: jump from page 0
        // to the anchor once the target chapter has paginated, and commit the
        // resolved page so progress does not stick to the chapter start.
        host.applyPendingAnchor()
        host.onPaginationReady?()
      } else if type == "pageCountUpdate", let total = body["totalPages"] as? Int {
        // Handle incremental layout updates from the extent watchers
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        let normalizedTotal = max(1, total)
        if host.totalPagesInChapter != normalizedTotal {
          host.rendererDidProducePageCount(normalizedTotal, navigationID: paginationNavigationID)
        }
        // The keep-page pass tracks the chapter end when the reader was on
        // the last page; adopt where it landed without re-scrolling.
        if let currentPage = body["currentPage"] as? Int, host.currentSubPageIndex != currentPage {
          host.currentSubPageIndex = currentPage
          host.rendererDidAdjustPageIndex(currentPage, navigationID: paginationNavigationID)
        }
        host.updateOverlayLabels()
      } else if type == "writingModeMismatch" {
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        // The content probe found publisher-declared vertical writing that
        // the manifest missed; re-lay out once with the vertical variant.
        guard !detectedVerticalLayout else { return }
        detectedVerticalLayout = true
        refreshDocumentStartUserScript()
        applyPagination(scrollToPage: host.currentSubPageIndex)
      }
    }
  }
#endif
