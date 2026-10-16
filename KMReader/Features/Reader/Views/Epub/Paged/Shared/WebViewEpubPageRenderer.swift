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
      }
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

      injectCSS { [weak self] in
        guard let self else { return }
        self.injectPaginationJS(
          targetPageIndex: pageIndex,
          preferLastPage: self.host?.preferLastPageOnReady ?? false
        )
      }
    }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: configuration.publicationLanguage,
        readingProgression: configuration.publicationReadingProgression
      )
    }

    private func injectCSS(completion: (() -> Void)? = nil) {
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: configuration.contentCSS,
        readiumProperties: configuration.readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: configuration.publicationLanguage,
        readingProgression: configuration.publicationReadingProgression
      )
      webView.evaluateJavaScript(js) { _, _ in
        completion?()
      }
    }

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool) {
      paginationGeneration += 1
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout,
        generation: paginationGeneration
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
        DispatchQueue.main.async(execute: completion)
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
        // Check if this is an internal link (same book navigation)
        if url.scheme == "file" {
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

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let host, let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }

      if type == "ready" {
        // A superseded pagination pass must not resurrect stale counts or positions.
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          var actualPage = body["currentPage"] as? Int ?? host.currentSubPageIndex

          host.rendererDidProducePageCount(normalizedTotal)

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
          if host.currentSubPageIndex != actualPage {
            host.currentSubPageIndex = actualPage
            host.onPageIndexAdjusted?(actualPage)
          }

          host.preferLastPageOnReady = false
          host.updateOverlayLabels()
        }

        // Stop the loading indicator and finally show the WebView content.
        host.rendererStopLoading()
        webView.alpha = 1
        host.onPaginationReady?()
      } else if type == "pageCountUpdate", let total = body["totalPages"] as? Int {
        // Handle incremental layout updates from ResizeObserver
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        let normalizedTotal = max(1, total)
        if host.totalPagesInChapter != normalizedTotal {
          host.rendererDidProducePageCount(normalizedTotal)
          host.updateOverlayLabels()
        }
      }
    }
  }
#endif
