//
// ScrolledEpubViewController.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  /// A view controller that displays a single EPUB chapter with continuous vertical scrolling.
  @MainActor
  final class ScrolledEpubViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
    UIScrollViewDelegate, UIGestureRecognizerDelegate
  {
    private enum BoundaryDirection {
      case previousChapter
      case nextChapter
    }

    private var webView: WKWebView!
    private var chapterIndex: Int
    private var currentSubPageIndex: Int = 0
    private var totalPagesInChapter: Int = 1
    private var containerInsets: UIEdgeInsets
    private var tapScrollPercentage: Double
    private var animateTapTurns: Bool
    private var theme: ReaderTheme
    private var contentCSS: String
    private var readiumProperties: [String: String?]
    private var publicationLanguage: String?
    private var publicationReadingProgression: WebPubReadingProgression?
    private var chapterURL: URL?
    private var chapterMediaType: String?
    private var rootURL: URL?
    private var mediaTypesByRelativePath: [String: String]
    private var lastLayoutSize: CGSize = .zero
    private var isContentLoaded = false
    private var pendingDestination: EpubNavigationDestination?
    private var readyToken: Int = 0
    private var lastKnownDocumentScrollTop: CGFloat = 0
    private var lastKnownDocumentContentHeight: CGFloat = 0
    private var lastKnownDocumentViewportHeight: CGFloat = 0

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
    /// Registers in-book links before asynchronous navigation begins.
    var onLinkTap: ((URL) -> Void)?
    /// Exposes the current link command without consuming it.
    var requiresFullExtentProvider: ((Int) -> Bool)?
    var pendingAnchorProvider: ((Int) -> EpubAnchorNavigation?)?

    var currentChapterIndex: Int { chapterIndex }
    var currentPageIndex: Int { currentSubPageIndex }

    private let epubResourceSchemeHandler = EpubResourceSchemeHandler()
    private let linkTouchArm = WebPubLinkTouchArm()

    private var containerView: UIView?
    private var containerConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?

    // Overlay labels
    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?
    private var topBoundaryIndicatorView: UIVisualEffectView?
    private var bottomBoundaryIndicatorView: UIVisualEffectView?
    private var topBoundaryIconView: UIImageView?
    private var bottomBoundaryIconView: UIImageView?
    private var boundaryHintHideWorkItem: DispatchWorkItem?

    private var loadingIndicator: UIActivityIndicatorView?

    // Tap gesture handling
    var onCenterTap: (() -> Void)?
    var onEndReached: (() -> Void)?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var isBoundaryTransitionInFlight = false
    private var boundaryReadyDirection: BoundaryDirection?
    private let documentBoundaryTolerance: CGFloat = 4
    private let boundaryOverscrollThreshold: CGFloat = 48
    private let boundaryHintDuration: TimeInterval = 0.6
    private let boundaryTransitionDelay: TimeInterval = 0.14

    init(
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      mediaTypesByRelativePath: [String: String],
      containerInsets: UIEdgeInsets,
      tapScrollPercentage: Double,
      animateTapTurns: Bool,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      chapterIndex: Int,
      initialSubPageIndex: Int,
      destination: EpubNavigationDestination?,
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
      self.tapScrollPercentage = Self.normalizedTapScrollPercentage(tapScrollPercentage)
      self.animateTapTurns = animateTapTurns
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.chapterIndex = chapterIndex
      self.currentSubPageIndex = max(0, initialSubPageIndex)
      self.pendingDestination = destination
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
      webView.scrollView.delegate = self
      refreshDocumentStartUserScript()
      webView.scrollView.isScrollEnabled = true
      webView.scrollView.bounces = true
      webView.scrollView.alwaysBounceVertical = true
      webView.scrollView.alwaysBounceHorizontal = false
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
      tapRecognizer.require(toFail: webView.scrollView.panGestureRecognizer)
      view.addGestureRecognizer(longPressRecognizer)
      self.longPressGestureRecognizer = longPressRecognizer
    }

    private func setupOverlayLabels() {
      let topOffset = labelTopOffset
      let bottomOffset = -labelBottomOffset

      infoOverlay = WebPubInfoOverlaySupport.UIKitOverlay(
        containerView: view,
        topAnchor: topAnchor,
        bottomAnchor: bottomAnchor,
        topOffset: labelTopOffset,
        bottomOffset: labelBottomOffset,
        theme: theme
      )

      let topIndicator = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      topIndicator.translatesAutoresizingMaskIntoConstraints = false
      topIndicator.layer.cornerRadius = 18
      topIndicator.clipsToBounds = true
      topIndicator.alpha = 0
      topIndicator.isUserInteractionEnabled = false
      let topIcon = UIImageView(image: UIImage(systemName: "chevron.up"))
      topIcon.translatesAutoresizingMaskIntoConstraints = false
      topIcon.contentMode = .scaleAspectFit
      topIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
      topIndicator.contentView.addSubview(topIcon)
      NSLayoutConstraint.activate([
        topIcon.centerXAnchor.constraint(equalTo: topIndicator.contentView.centerXAnchor),
        topIcon.centerYAnchor.constraint(equalTo: topIndicator.contentView.centerYAnchor),
        topIcon.widthAnchor.constraint(equalToConstant: 20),
        topIcon.heightAnchor.constraint(equalToConstant: 20),
      ])
      view.addSubview(topIndicator)
      NSLayoutConstraint.activate([
        topIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        topIndicator.topAnchor.constraint(equalTo: topAnchor, constant: topOffset + 14),
        topIndicator.widthAnchor.constraint(equalToConstant: 40),
        topIndicator.heightAnchor.constraint(equalToConstant: 40),
      ])
      self.topBoundaryIndicatorView = topIndicator
      self.topBoundaryIconView = topIcon

      let bottomIndicator = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      bottomIndicator.translatesAutoresizingMaskIntoConstraints = false
      bottomIndicator.layer.cornerRadius = 18
      bottomIndicator.clipsToBounds = true
      bottomIndicator.alpha = 0
      bottomIndicator.isUserInteractionEnabled = false
      let bottomIcon = UIImageView(image: UIImage(systemName: "chevron.down"))
      bottomIcon.translatesAutoresizingMaskIntoConstraints = false
      bottomIcon.contentMode = .scaleAspectFit
      bottomIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
      bottomIndicator.contentView.addSubview(bottomIcon)
      NSLayoutConstraint.activate([
        bottomIcon.centerXAnchor.constraint(equalTo: bottomIndicator.contentView.centerXAnchor),
        bottomIcon.centerYAnchor.constraint(equalTo: bottomIndicator.contentView.centerYAnchor),
        bottomIcon.widthAnchor.constraint(equalToConstant: 20),
        bottomIcon.heightAnchor.constraint(equalToConstant: 20),
      ])
      view.addSubview(bottomIndicator)
      NSLayoutConstraint.activate([
        bottomIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        bottomIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomOffset - 14),
        bottomIndicator.widthAnchor.constraint(equalToConstant: 40),
        bottomIndicator.heightAnchor.constraint(equalToConstant: 40),
      ])
      self.bottomBoundaryIndicatorView = bottomIndicator
      self.bottomBoundaryIconView = bottomIcon
    }

    func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .scrolled,
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
      // A touch that landed on a link was already reported by the page JS;
      // skip the tap zone so a link tap cannot also scroll or toggle chrome.
      if linkTouchArm.consume() { return }

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

    private func tapReadingDirection() -> ReadingDirection {
      .vertical
    }

    private var tapScrollStepRatio: CGFloat {
      CGFloat(tapScrollPercentage / 100.0)
    }

    private func scrollToPreviousPage() {
      guard isContentLoaded else { return }
      let pageHeight = webView.bounds.height
      guard pageHeight > 0 else { return }
      let currentOffset = webView.scrollView.contentOffset.y
      if currentOffset <= 1 {
        if chapterIndex > 0 {
          onChapterNavigationNeeded?(chapterIndex - 1)
        }
        return
      }
      let step = pageHeight * tapScrollStepRatio
      let targetOffset = max(0, currentOffset - step)
      scrollToOffset(targetOffset)
    }

    private func scrollToNextPage() {
      guard isContentLoaded else { return }
      let pageHeight = webView.bounds.height
      guard pageHeight > 0 else { return }
      let contentHeight = webView.scrollView.contentSize.height
      let maxOffset = max(0, contentHeight - pageHeight)
      let currentOffset = webView.scrollView.contentOffset.y
      if currentOffset >= maxOffset - 1 {
        if chapterIndex < totalChapters - 1 {
          onChapterNavigationNeeded?(chapterIndex + 1)
        } else {
          onEndReached?()
        }
        return
      }
      let step = pageHeight * tapScrollStepRatio
      let targetOffset = min(maxOffset, currentOffset + step)
      scrollToOffset(targetOffset)
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
      topBoundaryIconView?.tintColor = theme.uiColorText.withAlphaComponent(0.9)
      bottomBoundaryIconView?.tintColor = theme.uiColorText.withAlphaComponent(0.9)
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
      tapScrollPercentage: Double,
      animateTapTurns: Bool,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      chapterIndex: Int,
      navigationID: UUID,
      navigationRequest: EpubNavigationRequest?,
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
      let normalizedTapScrollPercentage = Self.normalizedTapScrollPercentage(tapScrollPercentage)
      let appearanceChanged =
        theme != self.theme
        || containerInsets != self.containerInsets
        || normalizedTapScrollPercentage != self.tapScrollPercentage
        || animateTapTurns != self.animateTapTurns
        || contentCSS != self.contentCSS
        || readiumProperties != self.readiumProperties
        || publicationLanguage != self.publicationLanguage
        || publicationReadingProgression != self.publicationReadingProgression
        || labelTopOffset != self.labelTopOffset
        || labelBottomOffset != self.labelBottomOffset
        || useSafeArea != self.useSafeArea

      let navigationChanged = navigationRequest != nil && self.navigationID != navigationID
      if navigationChanged || shouldReload || appearanceChanged {
        pendingDestination = navigationRequest?.destination ?? .page(currentSubPageIndex)
      }

      self.navigationID = navigationID
      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      epubResourceSchemeHandler.configure(rootURL: rootURL, mediaTypesByRelativePath: mediaTypesByRelativePath)
      self.containerInsets = containerInsets
      self.tapScrollPercentage = normalizedTapScrollPercentage
      self.animateTapTurns = animateTapTurns
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
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
        applyPagination(
          scrollToPage: pendingDestination?.estimatedPageIndex(pageCount: totalPagesInChapter) ?? currentSubPageIndex)
      }
    }

    private static func normalizedTapScrollPercentage(_ value: Double) -> Double {
      min(100.0, max(25.0, value))
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
      readyToken += 1
      lastKnownDocumentScrollTop = 0
      lastKnownDocumentContentHeight = 0
      lastKnownDocumentViewportHeight = 0
      totalPagesInChapter = 1
      webView.alpha = 0.01
      loadingIndicator?.startAnimating()
      refreshDocumentStartUserScript()

      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    /// Installs the CSS/theme payload as a document-start user script so the
    /// first paint already has the theme applied, shrinking the white flash.
    private func refreshDocumentStartUserScript() {
      guard isViewLoaded else { return }
      let controller = webView.configuration.userContentController
      controller.removeAllUserScripts()
      let js = WebPubThemeJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      )
      controller.addUserScript(
        WKUserScript(
          source: js,
          injectionTime: .atDocumentStart,
          forMainFrameOnly: true
        ))
    }

    private func reportCurrentPosition(resolvedAnchor: String? = nil) {
      onPageDidChange?(
        EpubPageLanding(
          chapterIndex: chapterIndex, pageIndex: currentSubPageIndex,
          layout: .content(pageCount: totalPagesInChapter), navigationID: renderedNavigationID,
          resolvedAnchor: resolvedAnchor
        ))
    }

    /// Scrolls to an in-document anchor (footnote, cross-reference).
    private func scrollToAnchor(_ anchor: String, completion: @escaping (Bool) -> Void) {
      guard isContentLoaded else {
        completion(false)
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToDocumentAnchorScript(anchor: anchor)
      let requestID = navigationID
      webView.evaluateJavaScript(js) { [weak self] result, error in
        guard let self, self.navigationID == requestID else { return }
        if error != nil {
          completion(false)
        } else {
          completion((result as? Bool) ?? false)
        }
      }
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

      decisionHandler(.cancel)
      onLinkTap?(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(
        scrollToPage: pendingDestination?.estimatedPageIndex(pageCount: totalPagesInChapter) ?? currentSubPageIndex)
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

      readyToken += 1
      let currentReadyToken = readyToken
      paginationNavigationID = navigationID
      injectCSS(
        contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      ) { [weak self] in
        guard let self, currentReadyToken == readyToken else { return }
        self.injectPaginationJS(
          targetPageIndex: pageIndex,
          preferLastPage: self.pendingDestination == .lastPage,
          token: currentReadyToken
        )
      }
    }

    private func scrollToPage(_ pageIndex: Int, animated: Bool = true) {
      guard isContentLoaded else { return }
      let targetOffset = scrollPagination.offset(for: pageIndex)

      scrollDocument(to: targetOffset, animated: animated)
    }

    private func scrollToOffset(_ targetOffset: CGFloat, animated: Bool = true) {
      guard isContentLoaded else { return }
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }
      let contentHeight = effectiveContentHeight
      let maxOffset = max(0, contentHeight - pageHeight)
      let clampedOffset = min(max(0, targetOffset), maxOffset)

      scrollDocument(to: clampedOffset, animated: animated)

      let newPageIndex = scrollPagination.pageIndex(at: clampedOffset)
      let clampedIndex = max(0, min(totalPagesInChapter - 1, newPageIndex))
      if clampedIndex != currentSubPageIndex {
        currentSubPageIndex = clampedIndex
        updateOverlayLabels()
        reportCurrentPosition()
      }
    }

    private var scrollPagination: EpubScrollPagination {
      EpubScrollPagination(contentHeight: effectiveContentHeight, viewportHeight: effectiveViewportHeight)
    }

    private var effectiveViewportHeight: CGFloat {
      let domViewportHeight = lastKnownDocumentViewportHeight
      if domViewportHeight > 0 {
        return domViewportHeight
      }
      return webView.bounds.height
    }

    private var effectiveContentHeight: CGFloat {
      max(
        webView.scrollView.contentSize.height,
        lastKnownDocumentContentHeight,
        effectiveViewportHeight
      )
    }

    private var isNearDocumentTop: Bool {
      lastKnownDocumentScrollTop <= documentBoundaryTolerance
    }

    private var isNearDocumentBottom: Bool {
      let maxOffset = max(0, effectiveContentHeight - effectiveViewportHeight)
      return lastKnownDocumentScrollTop >= max(0, maxOffset - documentBoundaryTolerance)
    }

    private func scrollDocument(to targetOffset: CGFloat, animated: Bool) {
      let clampedOffset = max(0, targetOffset)
      lastKnownDocumentScrollTop = clampedOffset
      let offset = Double(clampedOffset)
      let duration = animated && animateTapTurns ? 0.3 : 0
      let js = WebPubPagedJavaScriptBuilder.makeScrollDocumentScript(
        targetOffset: offset, duration: duration, token: readyToken
      )

      webView.evaluateJavaScript(js, completionHandler: nil)
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

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool, token: Int) {
      let js = WebPubPagedJavaScriptBuilder.makeScrolledPaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        token: token,
        requiresFullExtent: pendingDestination?.progression != nil || requiresFullExtentProvider?(chapterIndex) == true,
        waitForStableLayout: true,
        targetProgression: pendingDestination?.progression
      )

      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }
      guard paginationNavigationID == navigationID else { return }
      if let token = body["token"] as? Int, token != readyToken {
        return
      }

      if type == "linkTouch" {
        linkTouchArm.arm()
        return
      }

      updateDocumentMetrics(from: body)

      if let total = body["totalPages"] as? Int {
        let normalizedTotal = max(1, total)
        if type == "ready" || normalizedTotal != totalPagesInChapter {
          totalPagesInChapter = normalizedTotal
          onPageCountReady?(chapterIndex, normalizedTotal, paginationNavigationID)
        } else {
          totalPagesInChapter = normalizedTotal
        }
      }

      if type == "ready" {
        renderedNavigationID = paginationNavigationID
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          let actualPage = max(0, min(normalizedTotal - 1, body["currentPage"] as? Int ?? currentSubPageIndex))

          currentSubPageIndex = actualPage

          // Land on a pending in-book anchor (cross-chapter link) now that
          // the document is laid out.
          if let anchor = pendingAnchorProvider?(chapterIndex) {
            scrollToAnchor(anchor.anchor) { [weak self] found in
              guard let self, navigationID == anchor.id else { return }
              if !found { scrollToPage(0, animated: false) }
              let requestID = navigationID
              webView.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
                guard let self, navigationID == requestID else { return }
                lastKnownDocumentScrollTop = (result as? Double) ?? 0
                currentSubPageIndex = scrollPagination.pageIndex(at: lastKnownDocumentScrollTop)
                updateOverlayLabels()
                reportCurrentPosition(resolvedAnchor: anchor.anchor)
              }
            }
          }
        }

        pendingDestination = nil
        updateOverlayLabels()
        loadingIndicator?.stopAnimating()
        webView.alpha = 1
        reportCurrentPosition()
      } else if type == "scroll" {
        let actualPage = max(
          0,
          min(totalPagesInChapter - 1, body["currentPage"] as? Int ?? currentSubPageIndex)
        )
        if currentSubPageIndex != actualPage {
          currentSubPageIndex = actualPage
          updateOverlayLabels()
          reportCurrentPosition()
        }
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
      let js = WebPubThemeJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: css,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: readiumPropertyKeys,
        language: language,
        readingProgression: readingProgression
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard isContentLoaded else { return }
      guard !isBoundaryTransitionInFlight else { return }

      let pageHeight = webView.bounds.height
      guard pageHeight > 0 else { return }

      let maxOffset = max(0, scrollView.contentSize.height - pageHeight)
      let topOverscroll = max(0, -scrollView.contentOffset.y)
      let bottomOverscroll = max(0, scrollView.contentOffset.y - maxOffset)

      var candidateDirection: BoundaryDirection?
      var overscrollDistance: CGFloat = 0

      if topOverscroll > 0, chapterIndex > 0, isNearDocumentTop, topOverscroll >= bottomOverscroll {
        candidateDirection = .previousChapter
        overscrollDistance = topOverscroll
      } else if bottomOverscroll > 0, chapterIndex < totalChapters - 1, isNearDocumentBottom {
        candidateDirection = .nextChapter
        overscrollDistance = bottomOverscroll
      }

      guard let candidateDirection, overscrollDistance >= boundaryOverscrollThreshold else {
        if boundaryReadyDirection != nil {
          boundaryReadyDirection = nil
          hideBoundaryHint()
        }
        return
      }

      if boundaryReadyDirection != candidateDirection {
        boundaryReadyDirection = candidateDirection
        showBoundaryHint(for: candidateDirection, autoHideAfter: nil)
        HapticFeedback.light()
      }
    }

    func scrollViewWillEndDragging(
      _ scrollView: UIScrollView,
      withVelocity velocity: CGPoint,
      targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
      guard isContentLoaded else { return }
      let pageHeight = webView.bounds.height
      guard pageHeight > 0 else { return }
      let maxOffset = max(0, scrollView.contentSize.height - pageHeight)
      guard let direction = boundaryReadyDirection else {
        hideBoundaryHint()
        return
      }

      switch direction {
      case .previousChapter:
        targetContentOffset.pointee = CGPoint(x: 0, y: 0)
      case .nextChapter:
        targetContentOffset.pointee = CGPoint(x: 0, y: maxOffset)
      }
      triggerBoundaryNavigation(direction)
    }

    private func triggerBoundaryNavigation(_ direction: BoundaryDirection) {
      guard !isBoundaryTransitionInFlight else { return }
      isBoundaryTransitionInFlight = true
      boundaryReadyDirection = nil
      showBoundaryHint(for: direction, autoHideAfter: boundaryHintDuration)

      DispatchQueue.main.asyncAfter(deadline: .now() + boundaryTransitionDelay) { [weak self] in
        guard let self else { return }
        switch direction {
        case .previousChapter:
          if self.chapterIndex > 0 {
            self.onChapterNavigationNeeded?(self.chapterIndex - 1)
          }
        case .nextChapter:
          if self.chapterIndex < self.totalChapters - 1 {
            self.onChapterNavigationNeeded?(self.chapterIndex + 1)
          } else {
            self.onEndReached?()
          }
        }
        self.isBoundaryTransitionInFlight = false
      }
    }

    private func showBoundaryHint(for direction: BoundaryDirection, autoHideAfter delay: TimeInterval? = nil) {
      boundaryHintHideWorkItem?.cancel()

      let showView: UIVisualEffectView?
      let hideView: UIVisualEffectView?
      let initialTransform: CGAffineTransform
      switch direction {
      case .previousChapter:
        showView = topBoundaryIndicatorView
        hideView = bottomBoundaryIndicatorView
        initialTransform = CGAffineTransform(translationX: 0, y: -10)
      case .nextChapter:
        showView = bottomBoundaryIndicatorView
        hideView = topBoundaryIndicatorView
        initialTransform = CGAffineTransform(translationX: 0, y: 10)
      }

      if let hideView {
        hideView.alpha = 0
      }
      guard let showView else { return }
      showView.transform = initialTransform
      UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
        showView.alpha = 1
        showView.transform = .identity
      }

      guard let delay else { return }
      let workItem = DispatchWorkItem { [weak self] in
        self?.hideBoundaryHint()
      }
      boundaryHintHideWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func hideBoundaryHint() {
      boundaryHintHideWorkItem?.cancel()
      boundaryHintHideWorkItem = nil
      UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
        self.topBoundaryIndicatorView?.alpha = 0
        self.bottomBoundaryIndicatorView?.alpha = 0
      }
    }

    private func updateCurrentPageFromScroll() {
      guard isContentLoaded else { return }
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }

      let scrollOffset =
        lastKnownDocumentViewportHeight > 0
        ? lastKnownDocumentScrollTop
        : webView.scrollView.contentOffset.y
      let newPageIndex = scrollPagination.pageIndex(at: scrollOffset)
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      if let view = touch.view, view is UIControl {
        return false
      }
      return true
    }
  }
#endif
