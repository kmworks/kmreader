//
// WebPubScrolledView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  /// A SwiftUI view that displays EPUB content in continuous vertical scroll mode.
  struct WebPubScrolledView: UIViewControllerRepresentable {
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
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ScrolledEpubViewController {
      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
      let currentLocation = viewModel.pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)
      let initialProgression = viewModel.initialProgression(for: chapterIndex)

      let theme = preferences.resolvedTheme(for: colorScheme)
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        flowStyle: .scrolled,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let vc = ScrolledEpubViewController(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: viewModel.containerInsetsForLabels().uiEdgeInsets,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        chapterIndex: chapterIndex,
        initialSubPageIndex: pageIndex,
        targetProgressionOnReady: initialProgression,
        totalChapters: viewModel.chapterCount,
        bookTitle: bookTitle,
        chapterTitle: currentLocation?.title,
        totalProgression: currentLocation.flatMap { location in
          viewModel.totalProgression(
            location: location,
            chapterProgress: nil
          )
        },
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        labelTopOffset: viewModel.labelTopOffset,
        labelBottomOffset: viewModel.labelBottomOffset,
        useSafeArea: viewModel.useSafeArea
      )

      vc.onCenterTap = onCenterTap
      vc.onEndReached = onEndReached
      vc.onChapterNavigationNeeded = { [weak viewModel] targetChapterIndex in
        guard let viewModel = viewModel else { return }

        // Determine if we're going forward or backward
        let currentChapterIndex = viewModel.currentChapterIndex
        let isGoingBackward = targetChapterIndex < currentChapterIndex

        if isGoingBackward {
          // Going to previous chapter - jump to last page
          viewModel.targetChapterIndex = targetChapterIndex
          viewModel.targetPageIndex = -1
        } else {
          // Going to next chapter - jump to first page
          viewModel.targetChapterIndex = targetChapterIndex
          viewModel.targetPageIndex = 0
        }
      }
      vc.onPageDidChange = { [weak viewModel] chapterIndex, pageIndex in
        guard let viewModel = viewModel else { return }
        let normalizedPageIndex = max(0, pageIndex)
        viewModel.currentChapterIndex = chapterIndex
        viewModel.currentPageIndex = normalizedPageIndex
        let pageCount = viewModel.chapterPageCount(at: chapterIndex) ?? 1
        if normalizedPageIndex >= pageCount {
          viewModel.updateChapterPageCount(normalizedPageIndex + 1, for: chapterIndex)
        }
        viewModel.pageDidChange()
      }
      vc.onPageCountReady = { [weak viewModel] chapterIndex, pageCount in
        Task { @MainActor in
          viewModel?.updateChapterPageCount(pageCount, for: chapterIndex)
        }
      }
      context.coordinator.viewController = vc

      return vc
    }

    func updateUIViewController(_ uiViewController: ScrolledEpubViewController, context: Context) {
      context.coordinator.parent = self
      uiViewController.onEndReached = onEndReached

      // Handle TOC navigation via targetPageIndex
      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        targetChapterIndex >= 0,
        targetChapterIndex < viewModel.chapterCount
      {
        let uiChapterIndex = uiViewController.currentChapterIndex
        let uiPageIndex = uiViewController.currentPageIndex
        let pageCount = viewModel.chapterPageCount(at: targetChapterIndex) ?? 1
        let isLastPageRequest = targetPageIndex < 0
        let normalizedPageIndex =
          isLastPageRequest
          ? max(0, pageCount - 1)
          : max(0, min(targetPageIndex, pageCount - 1))
        let shouldNavigate =
          targetChapterIndex != uiChapterIndex
          || normalizedPageIndex != uiPageIndex

        if shouldNavigate {
          // Check if this is a jump to the last page of a chapter (backward navigation)
          let isGoingBackward = targetChapterIndex < uiChapterIndex
          let isLastPageOfChapter = isLastPageRequest || normalizedPageIndex == max(0, pageCount - 1)

          // Navigate to target chapter and page
          uiViewController.navigateToPage(
            chapterIndex: targetChapterIndex,
            subPageIndex: normalizedPageIndex,
            jumpToLastPage: isGoingBackward && isLastPageOfChapter
          )

          // Clear targetPageIndex and update current page
          Task { @MainActor in
            viewModel.currentChapterIndex = targetChapterIndex
            viewModel.currentPageIndex = normalizedPageIndex
            viewModel.targetChapterIndex = nil
            viewModel.targetPageIndex = nil
            viewModel.pageDidChange()
          }
          return
        }

        Task { @MainActor in
          if viewModel.currentChapterIndex != targetChapterIndex
            || viewModel.currentPageIndex != normalizedPageIndex
          {
            viewModel.currentChapterIndex = targetChapterIndex
            viewModel.currentPageIndex = normalizedPageIndex
            viewModel.pageDidChange()
          }
          viewModel.targetChapterIndex = nil
          viewModel.targetPageIndex = nil
        }
      }

      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
      let currentLocation = viewModel.pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)

      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)

      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        flowStyle: .scrolled,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let chapterProgress =
        currentLocation?.pageCount ?? 0 > 0
        ? Double((currentLocation?.pageIndex ?? 0) + 1) / Double(currentLocation?.pageCount ?? 1)
        : nil
      let totalProgression = currentLocation.flatMap { location in
        viewModel.totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )
      }

      uiViewController.configure(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: containerInsets,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        chapterIndex: chapterIndex,
        totalChapters: viewModel.chapterCount,
        bookTitle: bookTitle,
        chapterTitle: currentLocation?.title,
        totalProgression: totalProgression,
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        labelTopOffset: viewModel.labelTopOffset,
        labelBottomOffset: viewModel.labelBottomOffset,
        useSafeArea: viewModel.useSafeArea
      )
    }

    class Coordinator: NSObject {
      var parent: WebPubScrolledView
      weak var viewController: ScrolledEpubViewController?

      init(_ parent: WebPubScrolledView) {
        self.parent = parent
      }
    }
  }

  // MARK: - ScrolledEpubViewController

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
    private var pendingPageIndex: Int?
    private var pendingJumpToLastPage: Bool = false
    private var targetProgressionOnReady: Double?
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
    var onPageDidChange: ((Int, Int) -> Void)?
    var onPageCountReady: ((Int, Int) -> Void)?

    var currentChapterIndex: Int { chapterIndex }
    var currentPageIndex: Int { currentSubPageIndex }

    private let epubResourceSchemeHandler = EpubResourceSchemeHandler()

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
      self.tapScrollPercentage = Self.normalizedTapScrollPercentage(tapScrollPercentage)
      self.animateTapTurns = animateTapTurns
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
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
      webView.scrollView.delegate = self
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

    func navigateToPage(chapterIndex: Int, subPageIndex: Int, jumpToLastPage: Bool = false) {
      // If navigating to a different chapter, reload the content
      if chapterIndex != self.chapterIndex {
        self.chapterIndex = chapterIndex
        self.pendingPageIndex = subPageIndex
        self.pendingJumpToLastPage = jumpToLastPage
        loadContentIfNeeded(force: true)
      } else {
        // Same chapter - always wait for ready message to ensure correct page count
        self.pendingPageIndex = subPageIndex
        self.pendingJumpToLastPage = jumpToLastPage
        if isContentLoaded {
          applyPagination(scrollToPage: subPageIndex)
        }
      }
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
      if shouldReload {
        loadContentIfNeeded(force: true)
      } else if appearanceChanged {
        applyPagination(scrollToPage: currentSubPageIndex)
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
      lastKnownDocumentScrollTop = 0
      lastKnownDocumentContentHeight = 0
      lastKnownDocumentViewportHeight = 0
      totalPagesInChapter = 1
      webView.alpha = 0.01
      loadingIndicator?.startAnimating()

      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(scrollToPage: pendingPageIndex ?? currentSubPageIndex)
      pendingPageIndex = nil
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
      injectCSS(
        contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      ) { [weak self] in
        self?.injectPaginationJS(
          targetPageIndex: pageIndex,
          preferLastPage: self?.pendingJumpToLastPage ?? false,
          token: currentReadyToken
        )
      }
    }

    private func scrollToPage(_ pageIndex: Int, animated: Bool = true) {
      guard isContentLoaded else { return }
      let pageHeight = effectiveViewportHeight
      guard pageHeight > 0 else { return }

      let contentHeight = effectiveContentHeight
      let maxOffset = max(0, contentHeight - pageHeight)
      let targetOffset = min(pageHeight * CGFloat(pageIndex), maxOffset)

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

      let newPageIndex = Int(round(clampedOffset / pageHeight))
      let clampedIndex = max(0, min(totalPagesInChapter - 1, newPageIndex))
      if clampedIndex != currentSubPageIndex {
        currentSubPageIndex = clampedIndex
        updateOverlayLabels()
        onPageDidChange?(chapterIndex, currentSubPageIndex)
      }
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
      let js = """
          (function() {
            var target = \(targetPageIndex);
            var preferLast = \(preferLastPage ? "true" : "false");
            var token = \(token);
            var hasFinalized = false;

            // Offsets past the first page depend on the full content extent;
            // finalizing while images are still in flight measures a short
            // document and lands mid-chapter once they load.
            var needsFullExtent = preferLast || target > 0;
            var imagesPending = function() {
              var imgs = document.images;
              if (!imgs) { return false; }
              for (var i = 0; i < imgs.length; i++) {
                var img = imgs[i];
                if (img.loading === 'lazy') { img.loading = 'eager'; }
                if (!img.complete) { return true; }
              }
              return false;
            };
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

            var startLayoutCheck = function() {
              var root = document.documentElement;
              var lastH = root.scrollHeight || document.body.scrollHeight;
              var stableCount = 0;
              var attempt = 0;

              var check = function() {
                if (hasFinalized) return;

                attempt++;
                var body = document.body;
                var scrolling = document.scrollingElement || root || body;
                var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
                var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
                var currentH = Math.max(
                  scrolling ? (scrolling.scrollHeight || 0) : 0,
                  root ? (root.scrollHeight || 0) : 0,
                  body ? (body.scrollHeight || 0) : 0,
                  bodyRectHeight,
                  rootRectHeight,
                  0
                );
                var pageHeight =
                  (window.visualViewport && window.visualViewport.height)
                  || window.innerHeight
                  || root.clientHeight;
                if (!pageHeight || pageHeight <= 0) { pageHeight = 1; }

                if (currentH === lastH && currentH > 0) {
                  stableCount++;
                } else {
                  stableCount = 0;
                  lastH = currentH;
                }

                var isProbablyReady = (stableCount >= 4);
                if (target > 0 && currentH <= pageHeight && attempt < 40) {
                  isProbablyReady = false;
                }

                var waitingForImages = needsFullExtent && attempt < 600 && imagesPending();
                if ((isProbablyReady || attempt >= 60) && !waitingForImages) {
                  finalize();
                } else {
                  window.requestAnimationFrame(check);
                }
              };
              window.requestAnimationFrame(check);
            };

            var globalTimeout = setTimeout(function() {
              finalize();
            }, 10000);

            var loadStarted = false;
            var startOnce = function() {
              if (loadStarted) return;
              loadStarted = true;
              clearTimeout(globalTimeout);
              startLayoutCheck();
            };

            if (document.readyState === 'complete') {
              startOnce();
            } else {
              if (document.readyState === 'interactive' || document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                  setTimeout(startOnce, 500);
                });
              }
              window.addEventListener('load', function() {
                startOnce();
              });
            }
          })();
        """

      webView.evaluateJavaScript(js, completionHandler: nil)
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
        if normalizedTotal != totalPagesInChapter {
          totalPagesInChapter = normalizedTotal
          onPageCountReady?(chapterIndex, normalizedTotal)
        } else {
          totalPagesInChapter = normalizedTotal
        }
      }

      if type == "ready" {
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          var actualPage = body["currentPage"] as? Int ?? currentSubPageIndex

          let shouldJumpToLastPage = pendingJumpToLastPage
          if shouldJumpToLastPage {
            actualPage = max(0, normalizedTotal - 1)
            scrollToPage(actualPage, animated: false)
            pendingJumpToLastPage = false
          }

          if !shouldJumpToLastPage,
            let progression = targetProgressionOnReady
          {
            let targetIndex = max(
              0,
              min(normalizedTotal - 1, Int(floor(Double(normalizedTotal) * progression)))
            )
            if targetIndex != actualPage {
              actualPage = targetIndex
              scrollToPage(targetIndex, animated: false)
            }
            targetProgressionOnReady = nil
          }

          if currentSubPageIndex != actualPage {
            currentSubPageIndex = actualPage
          }
        }

        updateOverlayLabels()
        loadingIndicator?.stopAnimating()
        webView.alpha = 1
        onPageDidChange?(chapterIndex, currentSubPageIndex)
      } else if type == "scroll" {
        let actualPage = max(
          0,
          min(totalPagesInChapter - 1, body["currentPage"] as? Int ?? currentSubPageIndex)
        )
        if currentSubPageIndex != actualPage {
          currentSubPageIndex = actualPage
          updateOverlayLabels()
          onPageDidChange?(chapterIndex, currentSubPageIndex)
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
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
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
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
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
      let newPageIndex = Int(round(scrollOffset / pageHeight))
      let clampedIndex = max(0, min(totalPagesInChapter - 1, newPageIndex))

      if clampedIndex != currentSubPageIndex {
        currentSubPageIndex = clampedIndex
        updateOverlayLabels()
        onPageDidChange?(chapterIndex, currentSubPageIndex)
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
