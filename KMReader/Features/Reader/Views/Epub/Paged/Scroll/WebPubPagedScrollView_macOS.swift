#if os(macOS)
  import AppKit
  import SwiftUI
  import WebKit

  struct WebPubPagedScrollView: NSViewRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let animatePageTransitions: Bool
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> PagedCoordinator {
      PagedCoordinator(parent: self)
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
  final class PagedCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSGestureRecognizerDelegate {
    let epubResourceSchemeHandler = EpubResourceSchemeHandler()
    private var parent: WebPubPagedScrollView
    private weak var rootView: NSView?
    private weak var webView: WKWebView?
    private var webViewConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?
    private var infoOverlay: WebPubInfoOverlaySupport.AppKitOverlay?

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
    private var animatePageTransitions = true

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      )
    }

    init(parent: WebPubPagedScrollView) {
      self.parent = parent
      super.init()
    }

    func bind(rootView: NSView, webView: WKWebView) {
      self.rootView = rootView
      self.webView = webView
      installOverlayIfNeeded()
    }

    func update(from parent: WebPubPagedScrollView) {
      self.parent = parent
      guard let webView else { return }

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

      chapterIndex = selectedChapterIndex
      chapterURL = nextChapterURL
      chapterMediaType = nextChapterMediaType
      rootURL = nextRootURL
      contentCSS = readiumPayload.css
      readiumProperties = readiumPayload.properties
      publicationLanguage = parent.viewModel.publicationLanguage
      publicationReadingProgression = parent.viewModel.publicationReadingProgression
      chapterTitle = currentLocation?.title
      totalProgression = currentLocation.flatMap { location in
        parent.viewModel.totalProgression(location: location, chapterProgress: nil)
      }
      animatePageTransitions = parent.animatePageTransitions

      if let targetChapterIndex = parent.viewModel.targetChapterIndex,
        let targetPageIndex = parent.viewModel.targetPageIndex,
        targetChapterIndex == chapterIndex
      {
        pendingPageIndex = max(0, targetPageIndex)
        pendingJumpToLastPage = targetPageIndex < 0
      } else {
        pendingPageIndex = max(0, selectedPageIndex)
      }

      rootView?.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      webView.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      applyTheme(theme)
      applyContentInsets()
      updateOverlayLabels()

      if shouldReload {
        targetProgressionOnReady = parent.viewModel.initialProgression(for: selectedChapterIndex)
        loadContent(in: webView)
        return
      }

      if appearanceChanged || parent.viewModel.targetChapterIndex != nil || parent.viewModel.targetPageIndex != nil {
        applyPagination(on: webView, targetPageIndex: max(0, selectedPageIndex))
      }
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
      webViewConstraints?.leading.constant = insets.left
      webViewConstraints?.trailing.constant = insets.right
    }

    private func applyTheme(_ theme: ReaderTheme) {
      infoOverlay?.apply(theme: theme)
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

    private func goToPreviousPage() {
      if currentSubPageIndex > 0 {
        let page = currentSubPageIndex - 1
        scrollToPage(page, animated: animatePageTransitions)
        commitPage(page)
        return
      }
      if chapterIndex > 0 {
        parent.viewModel.targetChapterIndex = chapterIndex - 1
        parent.viewModel.targetPageIndex = -1
      }
    }

    private func goToNextPage() {
      if currentSubPageIndex < totalPagesInChapter - 1 {
        let page = currentSubPageIndex + 1
        scrollToPage(page, animated: animatePageTransitions)
        commitPage(page)
        return
      }
      if chapterIndex < max(0, parent.viewModel.chapterCount - 1) {
        parent.viewModel.targetChapterIndex = chapterIndex + 1
        parent.viewModel.targetPageIndex = 0
      } else {
        parent.onEndReached()
      }
    }

    private func commitPage(_ pageIndex: Int) {
      currentSubPageIndex = max(0, pageIndex)
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
      commitPage(actualPage)
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
