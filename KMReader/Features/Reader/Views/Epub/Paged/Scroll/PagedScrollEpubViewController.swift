//
// PagedScrollEpubViewController.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  /// A view controller that displays a single EPUB chapter in horizontal paged mode.
  @MainActor
  final class PagedScrollEpubViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
    UIScrollViewDelegate, UIGestureRecognizerDelegate
  {
    private var webView: WKWebView!
    private var chapterIndex: Int
    private var currentSubPageIndex: Int = 0
    private var totalPagesInChapter: Int = 1
    private var containerInsets: UIEdgeInsets
    private var theme: ReaderTheme
    private var contentCSS: String
    private var readiumProperties: [String: String?]
    private var publicationLanguage: String?
    private var publicationReadingProgression: WebPubReadingProgression?
    private var animatePageTransitions: Bool
    private var chapterURL: URL?
    private var chapterMediaType: String?
    private var rootURL: URL?
    private var mediaTypesByRelativePath: [String: String]
    private var lastLayoutSize: CGSize = .zero
    private var isContentLoaded = false
    private var pendingPageIndex: Int?
    private var pendingJumpToLastPage: Bool = false
    var targetProgressionOnReady: Double?
    /// Generation counter of the latest pagination pass; stale JS callbacks
    /// from superseded passes are ignored.
    private var paginationGeneration: Int = 0
    /// Set when the content's computed writing mode declared vertical
    /// presentation while the manifest did not; never downgraded.
    private var detectedVerticalLayout = false

    /// Called when an in-book link target needs view-model navigation
    /// (cross-chapter links, images).
    var onLinkTap: ((URL) -> Void)?
    /// Called after a same-chapter anchor jump with the origin page, so the
    /// view model can push the in-book link back stack.
    var onAnchorJump: ((Int) -> Void)?
    /// Exposes the current link command without consuming it.
    var requiresFullExtentProvider: ((Int) -> Bool)?
    var pendingAnchorProvider: ((Int) -> EpubAnchorNavigation?)?
    var onPendingAnchorLanding: ((EpubAnchorNavigation) -> Bool)?

    private var bookTitle: String?
    private var chapterTitle: String?
    private var totalProgression: Double?
    private var overlayPreferences: EpubOverlayPreferences
    private var showingControls: Bool = false
    private var labelTopOffset: CGFloat
    private var labelBottomOffset: CGFloat
    private var useSafeArea: Bool

    // Chapter navigation
    private var totalChapters: Int = 1
    var onChapterNavigationNeeded: ((Int) -> Void)?
    var navigationID = UUID()
    private var paginationNavigationID = UUID()
    private var renderedNavigationID = UUID()
    var onPageDidChange: ((EpubPageLanding) -> Void)?
    var onPageCountReady: ((Int, Int, UUID) -> Void)?

    var currentChapterIndex: Int { chapterIndex }
    var currentPageIndex: Int { currentSubPageIndex }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: publicationLanguage,
        readingProgression: publicationReadingProgression,
        forceVertical: detectedVerticalLayout
      )
    }

    private let epubResourceSchemeHandler = EpubResourceSchemeHandler()

    private var containerView: UIView?
    private var containerConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?

    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?

    private var loadingIndicator: UIActivityIndicatorView?

    // Tap gesture handling
    var onCenterTap: (() -> Void)?
    var onEndReached: (() -> Void)?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var interactivePanStartOffsetX: CGFloat = 0
    private let pageTurnVelocityThreshold: CGFloat = 450
    private let pageTurnProgressThreshold: CGFloat = 0.5
    private let chapterOverscrollThreshold: CGFloat = 80
    private let boundaryResistanceFactor: CGFloat = 0.35

    init(
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      mediaTypesByRelativePath: [String: String],
      containerInsets: UIEdgeInsets,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      animatePageTransitions: Bool,
      chapterIndex: Int,
      initialSubPageIndex: Int,
      targetProgressionOnReady: Double?,
      totalChapters: Int,
      bookTitle: String?,
      chapterTitle: String?,
      totalProgression: Double?,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      labelTopOffset: CGFloat,
      labelBottomOffset: CGFloat,
      useSafeArea: Bool
    ) {
      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      self.containerInsets = containerInsets
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.animatePageTransitions = animatePageTransitions
      self.chapterIndex = chapterIndex
      self.currentSubPageIndex = max(0, initialSubPageIndex)
      self.targetProgressionOnReady = targetProgressionOnReady
      self.totalChapters = totalChapters
      self.bookTitle = bookTitle
      self.chapterTitle = chapterTitle
      self.totalProgression = totalProgression
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.labelTopOffset = labelTopOffset
      self.labelBottomOffset = labelBottomOffset
      self.useSafeArea = useSafeArea
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      setupWebView()
      setupOverlayLabels()
      setupTapGesture()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAppDidBecomeActive),
        name: UIApplication.didBecomeActiveNotification,
        object: nil
      )
      loadContentIfNeeded(force: true)
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    private var topAnchor: NSLayoutYAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor
    }
    private var bottomAnchor: NSLayoutYAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor
    }
    private var leadingAnchor: NSLayoutXAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.leadingAnchor : view.leadingAnchor
    }
    private var trailingAnchor: NSLayoutXAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.trailingAnchor : view.trailingAnchor
    }

    private func setupWebView() {
      let config = WKWebViewConfiguration()
      epubResourceSchemeHandler.configure(rootURL: rootURL, mediaTypesByRelativePath: mediaTypesByRelativePath)
      config.registerEpubResourceSchemeHandler(epubResourceSchemeHandler)
      config.defaultWebpagePreferences.preferredContentMode = .mobile
      let controller = WKUserContentController()
      // Use weak wrapper to avoid retain cycle
      controller.add(WeakWKScriptMessageHandler(delegate: self), name: "readerBridge")
      config.userContentController = controller

      // Set background to fill entire view (including safe area)
      view.backgroundColor = theme.uiColorBackground

      let container = UIView()
      container.backgroundColor = .clear
      view.addSubview(container)
      container.translatesAutoresizingMaskIntoConstraints = false

      // Container respects safe area (or view edges based on policy), with additional label spacing
      let top = container.topAnchor.constraint(equalTo: topAnchor, constant: containerInsets.top)
      let leading = container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInsets.left)
      let trailing = trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: containerInsets.right)
      let bottom = bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: containerInsets.bottom)
      containerConstraints = (top, leading, trailing, bottom)
      NSLayoutConstraint.activate([top, leading, trailing, bottom])
      containerView = container

      applyContainerInsets()

      webView = WKWebView(frame: .zero, configuration: config)
      webView.navigationDelegate = self
      refreshDocumentStartUserScript()
      webView.scrollView.delegate = self
      webView.scrollView.isScrollEnabled = false
      webView.scrollView.bounces = true
      webView.scrollView.alwaysBounceHorizontal = true
      webView.scrollView.alwaysBounceVertical = false
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.showsVerticalScrollIndicator = false
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.scrollView.isPagingEnabled = false
      webView.isOpaque = false
      webView.alpha = 0

      applyTheme()

      container.addSubview(webView)
      webView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        webView.topAnchor.constraint(equalTo: container.topAnchor),
        webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])

      let indicator = UIActivityIndicatorView(style: .medium)
      indicator.hidesWhenStopped = true
      indicator.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(indicator)
      NSLayoutConstraint.activate([
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      self.loadingIndicator = indicator
    }

    private func setupTapGesture() {
      let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      tapRecognizer.delegate = self
      tapRecognizer.cancelsTouchesInView = false
      view.addGestureRecognizer(tapRecognizer)
      self.tapGestureRecognizer = tapRecognizer

      let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
      longPressRecognizer.delegate = self
      longPressRecognizer.cancelsTouchesInView = false
      tapRecognizer.require(toFail: longPressRecognizer)
      view.addGestureRecognizer(longPressRecognizer)
      self.longPressGestureRecognizer = longPressRecognizer

      let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      panRecognizer.delegate = self
      panRecognizer.cancelsTouchesInView = false
      panRecognizer.maximumNumberOfTouches = 1
      tapRecognizer.require(toFail: panRecognizer)
      panRecognizer.require(toFail: longPressRecognizer)
      view.addGestureRecognizer(panRecognizer)
      self.panGestureRecognizer = panRecognizer
    }

    private func setupOverlayLabels() {
      infoOverlay = WebPubInfoOverlaySupport.UIKitOverlay(
        containerView: view,
        topAnchor: topAnchor,
        bottomAnchor: bottomAnchor,
        topOffset: labelTopOffset,
        bottomOffset: labelBottomOffset,
        theme: theme
      )
    }

    func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .paged,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        totalProgression: totalProgression,
        currentPageIndex: currentSubPageIndex,
        totalPagesInChapter: totalPagesInChapter,
        showingControls: showingControls,
        isRTL: publicationReadingProgression == .rtl,
        overlayPreferences: overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      let location = recognizer.location(in: view)
      let size = view.bounds.size
      guard size.width > 0, size.height > 0 else { return }

      let normalizedX = location.x / size.width
      let normalizedY = location.y / size.height

      let action = TapZoneHelper.action(
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        tapZoneMode: AppConfig.epubTapZoneMode,
        tapZoneInversionMode: AppConfig.epubTapZoneInversionMode,
        readingDirection: tapReadingDirection()
      )

      switch action {
      case .previous:
        scrollToPreviousPage()
      case .next:
        scrollToNextPage()
      case .toggleControls:
        onCenterTap?()
      }
    }

    @objc private func handleLongPress(_: UILongPressGestureRecognizer) {}

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
      guard isContentLoaded else { return }
      let pageWidth = webView.bounds.width
      guard pageWidth > 0 else { return }

      let maxOffset = max(0, CGFloat(max(0, totalPagesInChapter - 1)) * pageWidth)

      switch gesture.state {
      case .began:
        interactivePanStartOffsetX =
          paginationLayout.usesReverseScrollLeft
          ? CGFloat(currentSubPageIndex) * pageWidth
          : webView.scrollView.contentOffset.x
        if paginationLayout.usesReverseScrollLeft {
          scrollToLogicalOffset(interactivePanStartOffsetX, animated: false)
        } else {
          webView.scrollView.setContentOffset(
            CGPoint(x: interactivePanStartOffsetX, y: 0),
            animated: false
          )
        }
      case .changed:
        let translationX = logicalTranslationX(from: gesture)
        let rawOffset = interactivePanStartOffsetX - translationX
        let adjustedOffset = adjustedHorizontalOffset(
          rawOffset,
          maxOffset: maxOffset
        )
        if paginationLayout.usesReverseScrollLeft {
          scrollToLogicalOffset(adjustedOffset, animated: false)
        } else {
          webView.scrollView.setContentOffset(
            CGPoint(x: adjustedOffset, y: 0),
            animated: false
          )
        }
      case .ended:
        finishInteractivePan(
          gesture: gesture,
          pageWidth: pageWidth,
          maxOffset: maxOffset
        )
      case .cancelled, .failed:
        scrollToPage(currentSubPageIndex, animated: animatePageTransitions)
      default:
        break
      }
    }

    private func logicalTranslationX(from gesture: UIPanGestureRecognizer) -> CGFloat {
      let translationX = gesture.translation(in: view).x
      return paginationLayout.reversesHorizontalGestureDirection ? -translationX : translationX
    }

    private func logicalVelocityX(from gesture: UIPanGestureRecognizer) -> CGFloat {
      let velocityX = gesture.velocity(in: view).x
      return paginationLayout.reversesHorizontalGestureDirection ? -velocityX : velocityX
    }

    private func adjustedHorizontalOffset(_ rawOffset: CGFloat, maxOffset: CGFloat) -> CGFloat {
      if rawOffset < 0 {
        return rawOffset * boundaryResistanceFactor
      }

      if rawOffset > maxOffset {
        return maxOffset + (rawOffset - maxOffset) * boundaryResistanceFactor
      }

      return rawOffset
    }

    private func finishInteractivePan(
      gesture: UIPanGestureRecognizer,
      pageWidth: CGFloat,
      maxOffset: CGFloat
    ) {
      let translationX = logicalTranslationX(from: gesture)
      let velocityX = logicalVelocityX(from: gesture)
      let rawOffset = interactivePanStartOffsetX - translationX

      if rawOffset < -chapterOverscrollThreshold {
        if chapterIndex > 0 {
          // Snap back to the current page while the previous chapter loads;
          // programmatic offsets never rubber-band with scrolling disabled.
          scrollToPage(currentSubPageIndex, animated: true)
          onChapterNavigationNeeded?(chapterIndex - 1)
          return
        }
      } else if rawOffset > maxOffset + chapterOverscrollThreshold {
        if chapterIndex < totalChapters - 1 {
          scrollToPage(currentSubPageIndex, animated: true)
          onChapterNavigationNeeded?(chapterIndex + 1)
          return
        }
        scrollToPage(currentSubPageIndex, animated: true)
        onEndReached?()
        return
      }

      let currentPage = currentSubPageIndex
      let pageDelta = (rawOffset - interactivePanStartOffsetX) / pageWidth

      let targetPage: Int
      if velocityX <= -pageTurnVelocityThreshold {
        targetPage = min(totalPagesInChapter - 1, currentPage + 1)
      } else if velocityX >= pageTurnVelocityThreshold {
        targetPage = max(0, currentPage - 1)
      } else if pageDelta >= pageTurnProgressThreshold {
        targetPage = min(totalPagesInChapter - 1, currentPage + 1)
      } else if pageDelta <= -pageTurnProgressThreshold {
        targetPage = max(0, currentPage - 1)
      } else {
        targetPage = currentPage
      }

      scrollToPage(targetPage, animated: animatePageTransitions)
      if targetPage != currentSubPageIndex {
        currentSubPageIndex = targetPage
        updateOverlayLabels()
        reportCurrentPosition()
      }
    }

    private func tapReadingDirection() -> ReadingDirection {
      switch publicationReadingProgression {
      case .rtl:
        return .rtl
      case .ttb, .btt:
        return .vertical
      case .ltr, .auto, .none:
        return .ltr
      }
    }

    private func scrollToPreviousPage() {
      guard isContentLoaded else { return }

      // If at first page of chapter, try to go to previous chapter
      if currentSubPageIndex <= 0 {
        if chapterIndex > 0 {
          onChapterNavigationNeeded?(chapterIndex - 1)
        }
        return
      }

      let newIndex = currentSubPageIndex - 1
      scrollToPage(newIndex, animated: animatePageTransitions)
      currentSubPageIndex = newIndex
      updateOverlayLabels()
      reportCurrentPosition()
    }

    private func scrollToNextPage() {
      guard isContentLoaded else { return }

      // If at last page of chapter, try to go to next chapter
      if currentSubPageIndex >= totalPagesInChapter - 1 {
        if chapterIndex < totalChapters - 1 {
          onChapterNavigationNeeded?(chapterIndex + 1)
        } else {
          onEndReached?()
        }
        return
      }

      let newIndex = currentSubPageIndex + 1
      scrollToPage(newIndex, animated: animatePageTransitions)
      currentSubPageIndex = newIndex
      updateOverlayLabels()
      reportCurrentPosition()
    }

    private func applyTheme() {
      view.backgroundColor = theme.uiColorBackground
      containerView?.backgroundColor = .clear
      if webView != nil {
        webView.backgroundColor = theme.uiColorBackground
        webView.scrollView.backgroundColor = .clear
      }
      loadingIndicator?.color = theme.uiColorText

      // Update overlay label colors
      infoOverlay?.apply(theme: theme)
    }

    private func applyContainerInsets() {
      guard let containerConstraints else { return }
      containerConstraints.top.constant = containerInsets.top
      containerConstraints.leading.constant = containerInsets.left
      containerConstraints.trailing.constant = containerInsets.right
      containerConstraints.bottom.constant = containerInsets.bottom
      view.layoutIfNeeded()
    }

    func configure(
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      mediaTypesByRelativePath: [String: String],
      containerInsets: UIEdgeInsets,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      animatePageTransitions: Bool,
      chapterIndex: Int,
      navigationID: UUID,
      targetPageIndex: Int?,
      targetProgression: Double?,
      totalChapters: Int,
      bookTitle: String?,
      chapterTitle: String?,
      totalProgression: Double?,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      labelTopOffset: CGFloat,
      labelBottomOffset: CGFloat,
      useSafeArea: Bool
    ) {
      let shouldReload =
        chapterURL != self.chapterURL
        || chapterMediaType != self.chapterMediaType
        || rootURL != self.rootURL
        || mediaTypesByRelativePath != self.mediaTypesByRelativePath
      let appearanceChanged =
        theme != self.theme
        || containerInsets != self.containerInsets
        || contentCSS != self.contentCSS
        || readiumProperties != self.readiumProperties
        || publicationLanguage != self.publicationLanguage
        || publicationReadingProgression != self.publicationReadingProgression
        || labelTopOffset != self.labelTopOffset
        || labelBottomOffset != self.labelBottomOffset
        || useSafeArea != self.useSafeArea

      let navigationChanged: Bool
      if let targetPageIndex {
        let pageIndex = max(0, targetPageIndex)
        let preferLastPage = targetPageIndex < 0
        navigationChanged =
          self.navigationID != navigationID
          || pendingPageIndex != pageIndex
          || pendingJumpToLastPage != preferLastPage
          || targetProgressionOnReady != targetProgression
        pendingPageIndex = pageIndex
        pendingJumpToLastPage = preferLastPage
        targetProgressionOnReady = targetProgression
      } else {
        navigationChanged = false
      }

      self.navigationID = navigationID
      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      epubResourceSchemeHandler.configure(rootURL: rootURL, mediaTypesByRelativePath: mediaTypesByRelativePath)
      self.containerInsets = containerInsets
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.animatePageTransitions = animatePageTransitions
      self.chapterIndex = chapterIndex
      self.totalChapters = totalChapters
      self.bookTitle = bookTitle
      self.chapterTitle = chapterTitle
      self.totalProgression = totalProgression
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.labelTopOffset = labelTopOffset
      self.labelBottomOffset = labelBottomOffset
      self.useSafeArea = useSafeArea

      guard isViewLoaded else { return }

      updateOverlayLabels()

      if appearanceChanged {
        applyContainerInsets()
      }

      applyTheme()
      refreshDocumentStartUserScript()
      if shouldReload {
        loadContentIfNeeded(force: true)
      } else if appearanceChanged || navigationChanged {
        applyPagination(scrollToPage: pendingPageIndex ?? currentSubPageIndex)
      }
    }

    private func loadContentIfNeeded(force: Bool) {
      guard let chapterURL, let rootURL else { return }
      // The web view loads the chapter through the resource scheme, so the raw
      // chapter URL never matches; compare the rewritten scheme URL instead.
      let chapterSchemeURL = EpubResourceScheme.url(for: chapterURL, rootURL: rootURL)
      let urlMatches =
        chapterSchemeURL != nil && webView.url?.deletingFragment == chapterSchemeURL

      if urlMatches && isContentLoaded {
        applyPagination(scrollToPage: currentSubPageIndex)
        return
      }

      if !force && urlMatches {
        return
      }

      isContentLoaded = false
      detectedVerticalLayout = false
      paginationGeneration += 1
      webView.alpha = 0.01
      loadingIndicator?.startAnimating()
      refreshDocumentStartUserScript()

      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(scrollToPage: pendingPageIndex ?? currentSubPageIndex)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = view.bounds.size
      let webViewSize = webView?.bounds.size ?? .zero
      guard size.width > 0, size.height > 0 else {
        return
      }

      if webViewSize != lastLayoutSize {
        lastLayoutSize = webViewSize

        if webViewSize.width > 0 && webViewSize.height > 0 {
          refreshDisplay()
        }
      }
    }

    @objc private func handleAppDidBecomeActive() {
      refreshDisplay()
      updateOverlayLabels()
    }

    func refreshDisplay() {
      applyPagination(scrollToPage: currentSubPageIndex)
    }

    private func applyPagination(scrollToPage pageIndex: Int) {
      guard isViewLoaded else { return }
      guard isContentLoaded else { return }
      let size = webView.bounds.size
      guard size.width > 0, size.height > 0 else { return }

      if webView.alpha < 0.1 {
        webView.alpha = 0.01
        loadingIndicator?.startAnimating()
      }

      paginationGeneration += 1
      let generation = paginationGeneration
      paginationNavigationID = navigationID
      injectCSS(
        contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      ) { [weak self] in
        guard let self, generation == paginationGeneration else { return }
        self.injectPaginationJS(
          targetPageIndex: pageIndex,
          preferLastPage: self.pendingJumpToLastPage
        )
      }
    }

    private func scrollToPage(_ pageIndex: Int, animated: Bool = true) {
      guard isContentLoaded else { return }
      let pageWidth = webView.bounds.width
      guard pageWidth > 0 else { return }

      if paginationLayout.usesReverseScrollLeft {
        let logicalOffset = pageWidth * CGFloat(max(0, pageIndex))
        scrollToLogicalOffset(logicalOffset, animated: animated)
        return
      }

      let contentWidth = webView.scrollView.contentSize.width
      let maxOffset = max(0, contentWidth - webView.bounds.width)
      let targetOffset = min(pageWidth * CGFloat(pageIndex), maxOffset)

      webView.scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: animated)
    }

    private func scrollToLogicalOffset(_ offset: CGFloat, animated: Bool) {
      guard isContentLoaded else { return }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToLogicalOffsetScript(
        logicalOffset: Double(offset),
        animated: animated,
        paginationLayout: paginationLayout
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool) {
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout,
        generation: paginationGeneration,
        requiresFullExtent: targetProgressionOnReady != nil || requiresFullExtentProvider?(chapterIndex) == true
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Installs the CSS/theme payload as a document-start user script so the
    /// first paint already has the theme applied, shrinking the white flash.
    private func refreshDocumentStartUserScript() {
      guard isViewLoaded else { return }
      let controller = webView.configuration.userContentController
      controller.removeAllUserScripts()
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      controller.addUserScript(
        WKUserScript(
          source: js,
          injectionTime: .atDocumentStart,
          forMainFrameOnly: true
        ))
    }

    private func reportCurrentPosition() {
      onPageDidChange?(
        EpubPageLanding(
          chapterIndex: chapterIndex, pageIndex: currentSubPageIndex,
          pageCount: totalPagesInChapter, navigationID: renderedNavigationID
        ))
    }

    /// Scrolls to an in-document anchor (footnote, cross-reference) and
    /// lands on the page containing it. The completion reports the resolved
    /// page index, or nil when the anchor does not exist.
    private func scrollToAnchor(_ anchor: String, completion: @escaping (Int?) -> Void) {
      guard isContentLoaded else {
        completion(nil)
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToAnchorScript(
        anchor: anchor,
        paginationLayout: paginationLayout
      )
      let requestID = navigationID
      webView.evaluateJavaScript(js) { [weak self] result, error in
        guard let self, self.navigationID == requestID else { return }
        if error != nil {
          completion(nil)
        } else {
          completion(result as? Int)
        }
      }
    }

    private func isCurrentChapterURL(_ url: URL) -> Bool {
      guard let chapterURL else { return false }
      let base = url.deletingFragment
      if let rootURL,
        let chapterSchemeURL = EpubResourceScheme.url(for: chapterURL, rootURL: rootURL),
        base == chapterSchemeURL.deletingFragment
      {
        return true
      }
      return base.standardizedFileURL.path == chapterURL.standardizedFileURL.path
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

      // In-book links stay inside the reader; external links are opened by
      // the platform browser via the UI layer.
      let isInBook =
        url.scheme == EpubResourceScheme.scheme
        || url.scheme == "file"
        || url.scheme == nil
      guard isInBook else {
        decisionHandler(.cancel)
        return
      }

      if let fragment = url.fragment, !fragment.isEmpty,
        isCurrentChapterURL(url)
      {
        // Same-chapter anchor: land on the fragment in place, commit the
        // resolved page so overlay labels and progress follow the jump, and
        // let the host push the origin onto the link back stack.
        decisionHandler(.cancel)
        let originPage = currentSubPageIndex
        scrollToAnchor(fragment) { [weak self] page in
          guard let self else { return }
          if let page {
            self.currentSubPageIndex = page
            self.updateOverlayLabels()
            self.reportCurrentPosition()
            self.onAnchorJump?(originPage)
          } else {
            self.onLinkTap?(url)
          }
        }
        return
      }

      decisionHandler(.cancel)
      onLinkTap?(url)
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }
      guard paginationNavigationID == navigationID else { return }

      if type == "ready" {
        if let generation = body["generation"] as? Int,
          generation != paginationGeneration
        {
          return
        }
        renderedNavigationID = paginationNavigationID
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          var actualPage = body["currentPage"] as? Int ?? currentSubPageIndex

          totalPagesInChapter = normalizedTotal
          onPageCountReady?(chapterIndex, normalizedTotal, paginationNavigationID)

          let shouldJumpToLastPage = pendingJumpToLastPage
          if shouldJumpToLastPage {
            pendingJumpToLastPage = false
          } else if let progression = targetProgressionOnReady {
            let targetIndex = max(0, min(normalizedTotal - 1, Int(floor(Double(normalizedTotal) * progression))))
            if targetIndex != actualPage {
              actualPage = targetIndex
              scrollToPage(targetIndex, animated: false)
            }
            targetProgressionOnReady = nil
          }

          if currentSubPageIndex != actualPage {
            currentSubPageIndex = actualPage
          }

          // Land on a pending in-book anchor (cross-chapter link) now that
          // pagination settled, and commit the resolved page so progress does
          // not stick to the chapter start.
          if let anchor = pendingAnchorProvider?(chapterIndex) {
            scrollToAnchor(anchor.anchor) { [weak self] resolvedPage in
              guard let self, onPendingAnchorLanding?(anchor) == true else { return }
              let page = resolvedPage ?? 0
              if resolvedPage == nil { scrollToPage(0, animated: false) }
              self.currentSubPageIndex = page
              self.updateOverlayLabels()
              self.reportCurrentPosition()
            }
          }
        }

        pendingPageIndex = nil
        updateOverlayLabels()
        loadingIndicator?.stopAnimating()
        webView.alpha = 1
        reportCurrentPosition()
      } else if type == "pageCountUpdate" {
        if let generation = body["generation"] as? Int,
          generation != paginationGeneration
        {
          return
        }
        guard let total = body["totalPages"] as? Int else { return }
        let normalizedTotal = max(1, total)
        if let currentPage = body["currentPage"] as? Int,
          currentPage != currentSubPageIndex
        {
          currentSubPageIndex = min(max(0, currentPage), normalizedTotal - 1)
        }
        if totalPagesInChapter != normalizedTotal {
          totalPagesInChapter = normalizedTotal
          onPageCountReady?(chapterIndex, normalizedTotal, paginationNavigationID)
        }
        updateOverlayLabels()
      } else if type == "writingModeMismatch" {
        if let generation = body["generation"] as? Int,
          generation != paginationGeneration
        {
          return
        }
        guard let vertical = body["vertical"] as? Bool, vertical,
          !detectedVerticalLayout
        else { return }
        detectedVerticalLayout = true
        refreshDocumentStartUserScript()
        applyPagination(scrollToPage: currentSubPageIndex)
      }
    }

    private func injectCSS(
      _ css: String,
      readiumProperties: [String: String?],
      readiumPropertyKeys: [String],
      language: String?,
      readingProgression: WebPubReadingProgression?,
      completion: (() -> Void)? = nil
    ) {
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: css,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: readiumPropertyKeys,
        language: language,
        readingProgression: readingProgression,
        forceVerticalLayout: detectedVerticalLayout
      )
      webView.evaluateJavaScript(js) { _, _ in
        completion?()
      }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      updateCurrentPageFromScroll()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate {
        updateCurrentPageFromScroll()
      }
    }

    func scrollViewWillEndDragging(
      _ scrollView: UIScrollView,
      withVelocity velocity: CGPoint,
      targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
      guard isContentLoaded else { return }
      guard !paginationLayout.usesReverseScrollLeft else { return }
      let pageWidth = webView.bounds.width
      guard pageWidth > 0 else { return }

      let targetOffset = targetContentOffset.pointee.x

      // Check if user is trying to scroll left from the first page
      if currentSubPageIndex == 0 {
        // Detect leftward scroll attempt (negative velocity or trying to scroll before start)
        if velocity.x < -0.1 || targetOffset < -pageWidth * 0.3 {
          if chapterIndex > 0 {
            // Cancel the scroll animation
            targetContentOffset.pointee = CGPoint(x: 0, y: 0)
            // Navigate to previous chapter
            onChapterNavigationNeeded?(chapterIndex - 1)
          }
          return
        }
      }

      // Check if user is trying to scroll right from the last page
      if currentSubPageIndex == totalPagesInChapter - 1 {
        let contentWidth = scrollView.contentSize.width
        let maxOffset = max(0, contentWidth - pageWidth)
        // Detect rightward scroll attempt (positive velocity or trying to scroll past end)
        if velocity.x > 0.1 || targetOffset > maxOffset + pageWidth * 0.3 {
          if chapterIndex < totalChapters - 1 {
            // Cancel the scroll animation
            targetContentOffset.pointee = CGPoint(x: maxOffset, y: 0)
            // Navigate to next chapter
            onChapterNavigationNeeded?(chapterIndex + 1)
          } else {
            onEndReached?()
          }
          return
        }
      }
    }

    private func updateCurrentPageFromScroll() {
      guard isContentLoaded else { return }
      guard !paginationLayout.usesReverseScrollLeft else { return }
      let pageWidth = webView.bounds.width
      guard pageWidth > 0 else { return }

      let scrollOffset = webView.scrollView.contentOffset.x
      let newPageIndex = Int(round(scrollOffset / pageWidth))
      let clampedIndex = max(0, min(totalPagesInChapter - 1, newPageIndex))

      if clampedIndex != currentSubPageIndex {
        currentSubPageIndex = clampedIndex
        updateOverlayLabels()
        reportCurrentPosition()
      }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // Allow tap gesture to work alongside scroll view gestures
      return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if let panGestureRecognizer,
        gestureRecognizer === panGestureRecognizer,
        let panGesture = gestureRecognizer as? UIPanGestureRecognizer
      {
        let velocity = panGesture.velocity(in: view)
        if velocity == .zero {
          return true
        }
        return abs(velocity.x) > abs(velocity.y)
      }
      return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      if let view = touch.view, view is UIControl {
        return false
      }
      return true
    }
  }
#endif
