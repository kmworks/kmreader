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
    private var readyToken: Int = 0
    private var lastKnownDocumentScrollTop: CGFloat = 0
    private var lastKnownDocumentContentHeight: CGFloat = 0
    private var lastKnownDocumentViewportHeight: CGFloat = 0
    private var chapterTitle: String?
    private var totalProgression: Double?
    private var animateTapTurns = true

    init(parent: WebPubScrolledView) {
      self.parent = parent
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

      if let targetChapterIndex = parent.viewModel.targetChapterIndex,
        let targetPageIndex = parent.viewModel.targetPageIndex,
        targetChapterIndex == chapterIndex
      {
        pendingPageIndex = max(0, targetPageIndex)
        pendingJumpToLastPage = targetPageIndex < 0
      } else {
        pendingPageIndex = max(0, selectedPageIndex)
      }

      if shouldReload {
        targetProgressionOnReady = parent.viewModel.initialProgression(for: selectedChapterIndex)
        loadContent(in: webView)
        return
      }

      rootView?.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      webView.layer?.backgroundColor = NSColor(hex: theme.backgroundColorHex)?.cgColor
      applyTheme(theme)
      applyContentInsets()
      updateOverlayLabels()

      if appearanceChanged || parent.viewModel.targetChapterIndex != nil || parent.viewModel.targetPageIndex != nil {
        applyPagination(on: webView, targetPageIndex: max(0, selectedPageIndex))
      } else if let currentLocation {
        updateViewModelLocation(from: currentLocation.pageIndex)
      }
    }

    private func loadContent(in webView: WKWebView) {
      guard let chapterURL, let rootURL else { return }
      isContentLoaded = false
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
      injectCSS(on: webView) { [weak self] in
        self?.injectPaginationJS(on: webView, targetPageIndex: targetPageIndex, token: token)
      }
    }

    private func scrollToPreviousPage() {
      guard chapterIndex >= 0 else { return }
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }
      let currentOffset = lastKnownDocumentScrollTop
      if currentOffset <= 1 {
        if chapterIndex > 0 {
          parent.viewModel.targetChapterIndex = chapterIndex - 1
          parent.viewModel.targetPageIndex = -1
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
          parent.viewModel.targetChapterIndex = chapterIndex + 1
          parent.viewModel.targetPageIndex = 0
        } else {
          parent.onEndReached()
        }
        return
      }
      let step = pageHeight * CGFloat(parent.tapScrollPercentage / 100.0)
      scrollDocument(to: min(maxOffset, currentOffset + step))
    }

    private func scrollDocument(to targetOffset: CGFloat) {
      guard let webView else { return }
      let clampedOffset = max(0, targetOffset)
      lastKnownDocumentScrollTop = clampedOffset
      let offset = Double(clampedOffset)
      let duration = animateTapTurns ? 0.3 : 0
      let js = """
          (function() {
            var top = \(offset);
            var duration = \(duration);
            var root = document.documentElement;
            var body = document.body;
            var scrolling = document.scrollingElement || root || body;
            var getCurrentTop = function() {
              return Math.max(
                0,
                window.scrollY
                || (scrolling && scrolling.scrollTop)
                || (root && root.scrollTop)
                || (body && body.scrollTop)
                || 0
              );
            };
            var setTop = function(value) {
              window.scrollTo(0, value);
              if (scrolling) { scrolling.scrollTop = value; }
              if (root) { root.scrollTop = value; }
              if (body) { body.scrollTop = value; }
            };
            var finish = function() {
              if (window.__kmreaderPostMetrics) {
                window.requestAnimationFrame(function() {
                  window.__kmreaderPostMetrics('scroll');
                });
              }
            };
            if (window.__kmreaderScrollAnimationFrame) {
              window.cancelAnimationFrame(window.__kmreaderScrollAnimationFrame);
              window.__kmreaderScrollAnimationFrame = null;
            }
            if (!(duration > 0)) {
              setTop(top);
              finish();
              return true;
            }
            var startTop = getCurrentTop();
            var distance = top - startTop;
            if (Math.abs(distance) < 0.5) {
              setTop(top);
              finish();
              return true;
            }
            var startTime = null;
            var easeOutCubic = function(progress) {
              return 1 - Math.pow(1 - progress, 3);
            };
            var step = function(timestamp) {
              if (startTime === null) {
                startTime = timestamp;
              }
              var progress = Math.min(1, (timestamp - startTime) / (duration * 1000));
              var eased = easeOutCubic(progress);
              setTop(startTop + (distance * eased));
              if (progress < 1) {
                window.__kmreaderScrollAnimationFrame = window.requestAnimationFrame(step);
                return;
              }
              window.__kmreaderScrollAnimationFrame = null;
              finish();
            };
            window.__kmreaderScrollAnimationFrame = window.requestAnimationFrame(step);
            return true;
          })();
        """
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(on: webView, targetPageIndex: pendingPageIndex ?? currentSubPageIndex)
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
      guard let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }
      if let token = body["token"] as? Int, token != readyToken {
        return
      }

      updateDocumentMetrics(from: body)

      if let total = body["totalPages"] as? Int {
        let normalizedTotal = max(1, total)
        totalPagesInChapter = normalizedTotal
        parent.viewModel.updateChapterPageCount(normalizedTotal, for: chapterIndex)
      }

      let actualPage = max(
        0,
        min(totalPagesInChapter - 1, body["currentPage"] as? Int ?? currentSubPageIndex)
      )

      if type == "ready" {
        var resolvedPage = actualPage
        if pendingJumpToLastPage {
          resolvedPage = max(0, totalPagesInChapter - 1)
          scrollDocument(to: effectiveViewportHeight * CGFloat(resolvedPage))
          pendingJumpToLastPage = false
        } else if let progression = targetProgressionOnReady {
          resolvedPage = max(
            0,
            min(totalPagesInChapter - 1, Int(floor(Double(totalPagesInChapter) * progression)))
          )
          if resolvedPage != actualPage {
            scrollDocument(to: effectiveViewportHeight * CGFloat(resolvedPage))
          }
          targetProgressionOnReady = nil
        }
        currentSubPageIndex = resolvedPage
      } else if currentSubPageIndex != actualPage {
        currentSubPageIndex = actualPage
      }

      updateViewModelLocation(from: currentSubPageIndex)
    }

    private func updateViewModelLocation(from pageIndex: Int) {
      let normalizedPageIndex = max(0, pageIndex)
      parent.viewModel.currentChapterIndex = chapterIndex
      parent.viewModel.currentPageIndex = normalizedPageIndex
      parent.viewModel.targetChapterIndex = nil
      parent.viewModel.targetPageIndex = nil
      parent.viewModel.pageDidChange()
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

    private var effectiveViewportHeight: CGFloat {
      max(1, lastKnownDocumentViewportHeight)
    }

    private var effectiveContentHeight: CGFloat {
      max(lastKnownDocumentContentHeight, effectiveViewportHeight)
    }

    private func injectPaginationJS(on webView: WKWebView, targetPageIndex: Int, token: Int) {
      let js = """
          (function() {
            var target = \(targetPageIndex);
            var token = \(token);
            var hasFinalized = false;
            var installMetricsBridge = function() {
              window.__kmreaderCurrentToken = token;
              if (window.__kmreaderPostMetrics) {
                return;
              }
              window.__kmreaderPostMetrics = function(type) {
                var root = document.documentElement;
                var body = document.body;
                var scrolling = document.scrollingElement || root || body;
                var viewportHeight =
                  (window.visualViewport && window.visualViewport.height)
                  || window.innerHeight
                  || (root && root.clientHeight)
                  || 1;
                if (!viewportHeight || viewportHeight <= 0) { viewportHeight = 1; }

                var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
                var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
                var contentHeight = Math.max(
                  scrolling ? (scrolling.scrollHeight || 0) : 0,
                  root ? (root.scrollHeight || 0) : 0,
                  body ? (body.scrollHeight || 0) : 0,
                  bodyRectHeight,
                  rootRectHeight,
                  viewportHeight
                );
                var maxScroll = Math.max(0, contentHeight - viewportHeight);
                var scrollTop = Math.max(
                  0,
                  Math.min(
                    maxScroll,
                    window.scrollY
                    || (scrolling && scrolling.scrollTop)
                    || (root && root.scrollTop)
                    || (body && body.scrollTop)
                    || 0
                  )
                );
                var total = Math.max(1, Math.ceil(contentHeight / viewportHeight));
                var currentPage = Math.max(
                  0,
                  Math.min(total - 1, Math.round(scrollTop / viewportHeight))
                );

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
                  window.webkit.messageHandlers.readerBridge.postMessage({
                    type: type,
                    token: window.__kmreaderCurrentToken || 0,
                    totalPages: total,
                    currentPage: currentPage,
                    scrollTop: scrollTop,
                    contentHeight: contentHeight,
                    viewportHeight: viewportHeight
                  });
                }
              };

              if (window.__kmreaderScrollMetricsInstalled) {
                return;
              }
              window.__kmreaderScrollMetricsInstalled = true;
              var scheduled = false;
              var scheduleMetrics = function(type) {
                if (scheduled) { return; }
                scheduled = true;
                window.requestAnimationFrame(function() {
                  scheduled = false;
                  window.__kmreaderPostMetrics(type || 'scroll');
                });
              };
              window.addEventListener('scroll', function() {
                scheduleMetrics('scroll');
              }, { passive: true });
              window.addEventListener('resize', function() {
                scheduleMetrics('scroll');
              });
              if (window.visualViewport) {
                window.visualViewport.addEventListener('resize', function() {
                  scheduleMetrics('scroll');
                }, { passive: true });
              }
            };

            var finalize = function() {
              if (hasFinalized) return;
              hasFinalized = true;
              installMetricsBridge();

              var root = document.documentElement;
              var body = document.body;
              var scrolling = document.scrollingElement || root || body;
              var pageHeight =
                (window.visualViewport && window.visualViewport.height)
                || window.innerHeight
                || root.clientHeight;
              if (!pageHeight || pageHeight <= 0) { pageHeight = 1; }

              var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
              var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
              var currentHeight = Math.max(
                scrolling ? (scrolling.scrollHeight || 0) : 0,
                root ? (root.scrollHeight || 0) : 0,
                body ? (body.scrollHeight || 0) : 0,
                bodyRectHeight,
                rootRectHeight,
                pageHeight
              );
              var total = Math.max(1, Math.ceil(currentHeight / pageHeight));
              var maxScroll = Math.max(0, currentHeight - pageHeight);
              var finalTarget = Math.max(0, Math.min(total - 1, target));
              var offset = Math.min(pageHeight * finalTarget, maxScroll);

              window.scrollTo(0, offset);
              if (document.documentElement) { document.documentElement.scrollTop = offset; }
              if (document.body) { document.body.scrollTop = offset; }

              setTimeout(function() {
                if (window.__kmreaderPostMetrics) {
                  window.__kmreaderPostMetrics('ready');
                }
              }, 60);
            };

            var timeout = setTimeout(finalize, 5000);
            var start = function() {
              clearTimeout(timeout);
              window.requestAnimationFrame(function() {
                window.requestAnimationFrame(finalize);
              });
            };

            if (document.readyState === 'complete') {
              start();
            } else {
              window.addEventListener('load', start, { once: true });
              document.addEventListener('DOMContentLoaded', start, { once: true });
            }
          })();
        """

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
