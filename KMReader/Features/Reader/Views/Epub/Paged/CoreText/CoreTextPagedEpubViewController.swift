#if os(iOS)
  import SwiftUI
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextPagedEpubViewController: UIViewController, UIPageViewControllerDataSource,
    UIPageViewControllerDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate
  {
    private let viewModel: EpubReaderViewModel
    private var preferences: EpubThemePreferences
    private var colorScheme: ColorScheme
    private var animatePageTransitions: Bool
    private var overlayPreferences: EpubOverlayPreferences
    private var showingControls: Bool
    private var bookTitle: String?
    private var onCenterTap: () -> Void
    private var onEndReached: () -> Void
    private var tapZoneMode: TapZoneMode
    private var tapZoneInversionMode: TapZoneInversionMode

    private var pageViewController: UIPageViewController!
    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?
    private var loadingIndicator: UIActivityIndicatorView?

    private var layoutTask: Task<Void, Never>?
    private var layoutOperation: CoreTextEpubLayoutOperation?
    private var layoutGeneration = 0
    private var displayLists: [DisplayList] = []
    private var linkRegions: [LinkInteractionRegionSet] = []
    private var chapterLoadFailed = false
    private var currentChapterIndex: Int
    private var currentPageIndex: Int
    private var pendingPageCommitIndex: Int?
    private var restoreProgression: Double?
    private var isContentReady = false
    private var lastLayoutSize: CGSize = .zero

    init(
      viewModel: EpubReaderViewModel,
      preferences: EpubThemePreferences,
      colorScheme: ColorScheme,
      animatePageTransitions: Bool,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      bookTitle: String?,
      onCenterTap: @escaping () -> Void,
      onEndReached: @escaping () -> Void,
      tapZoneMode: TapZoneMode,
      tapZoneInversionMode: TapZoneInversionMode
    ) {
      self.viewModel = viewModel
      self.preferences = preferences
      self.colorScheme = colorScheme
      self.animatePageTransitions = animatePageTransitions
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.bookTitle = bookTitle
      self.onCenterTap = onCenterTap
      self.onEndReached = onEndReached
      self.tapZoneMode = tapZoneMode
      self.tapZoneInversionMode = tapZoneInversionMode
      self.currentChapterIndex = viewModel.currentChapterIndex
      self.currentPageIndex = viewModel.currentPageIndex
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      layoutTask?.cancel()
      layoutOperation = nil
    }

    private var theme: ReaderTheme {
      preferences.resolvedTheme(for: colorScheme)
    }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: viewModel.publicationLanguage,
        readingProgression: viewModel.publicationReadingProgression
      )
    }

    private var displayedPageCount: Int {
      chapterLoadFailed ? 1 : displayLists.count
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = theme.uiColorBackground
      setupPageViewController()
      setupOverlay()
      setupGestures()
      showLoading()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = pageViewController.view.bounds.size
      guard size.width > 0, size.height > 0 else { return }
      viewModel.updateViewport(size: view.bounds.size)
      if lastLayoutSize == .zero {
        lastLayoutSize = size
        reloadChapter()
        return
      }
      guard size != lastLayoutSize else { return }
      lastLayoutSize = size
      reloadChapter(preservePosition: true)
    }

    func configure(
      preferences: EpubThemePreferences,
      colorScheme: ColorScheme,
      animatePageTransitions: Bool,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      bookTitle: String?,
      onCenterTap: @escaping () -> Void,
      onEndReached: @escaping () -> Void,
      tapZoneMode: TapZoneMode,
      tapZoneInversionMode: TapZoneInversionMode
    ) {
      let layoutAppearanceChanged =
        preferences != self.preferences
        || colorScheme != self.colorScheme

      self.preferences = preferences
      self.colorScheme = colorScheme
      self.animatePageTransitions = animatePageTransitions
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.bookTitle = bookTitle
      self.onCenterTap = onCenterTap
      self.onEndReached = onEndReached
      self.tapZoneMode = tapZoneMode
      self.tapZoneInversionMode = tapZoneInversionMode

      view.backgroundColor = theme.uiColorBackground
      infoOverlay?.apply(theme: theme)
      updateOverlayLabels()

      let shouldLoadContent =
        !isContentReady && layoutTask == nil && !viewModel.isLoading && viewModel.hasContent
        && viewModel.errorMessage == nil
      if layoutAppearanceChanged || shouldLoadContent {
        reloadChapter(preservePosition: true)
      } else {
        navigateToTargetIfNeeded()
      }
    }

    private var topAnchor: NSLayoutYAxisAnchor {
      viewModel.useSafeArea ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor
    }

    private var bottomAnchor: NSLayoutYAxisAnchor {
      viewModel.useSafeArea ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor
    }

    private var leadingAnchor: NSLayoutXAxisAnchor {
      viewModel.useSafeArea ? view.safeAreaLayoutGuide.leadingAnchor : view.leadingAnchor
    }

    private var trailingAnchor: NSLayoutXAxisAnchor {
      viewModel.useSafeArea ? view.safeAreaLayoutGuide.trailingAnchor : view.trailingAnchor
    }

    private func setupPageViewController() {
      pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: nil
      )
      pageViewController.dataSource = self
      pageViewController.delegate = self
      addChild(pageViewController)
      view.addSubview(pageViewController.view)
      pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      NSLayoutConstraint.activate([
        pageViewController.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInsets.left),
        trailingAnchor.constraint(equalTo: pageViewController.view.trailingAnchor, constant: containerInsets.right),
        pageViewController.view.topAnchor.constraint(equalTo: topAnchor, constant: containerInsets.top),
        bottomAnchor.constraint(equalTo: pageViewController.view.bottomAnchor, constant: containerInsets.bottom),
      ])
      pageViewController.didMove(toParent: self)
      if let scrollView = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
        scrollView.delegate = self
      }

      let indicator = UIActivityIndicatorView(style: .medium)
      indicator.hidesWhenStopped = true
      indicator.color = theme.uiColorText
      indicator.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(indicator)
      NSLayoutConstraint.activate([
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      loadingIndicator = indicator
    }

    private func setupOverlay() {
      infoOverlay = WebPubInfoOverlaySupport.UIKitOverlay(
        containerView: view,
        topAnchor: topAnchor,
        bottomAnchor: bottomAnchor,
        topOffset: viewModel.labelTopOffset,
        bottomOffset: viewModel.labelBottomOffset,
        theme: theme
      )
      updateOverlayLabels()
    }

    private func setupGestures() {
      let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      tapRecognizer.delegate = self
      tapRecognizer.cancelsTouchesInView = false
      if let scrollView = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
        tapRecognizer.require(toFail: scrollView.panGestureRecognizer)
      }
      view.addGestureRecognizer(tapRecognizer)
    }

    private func showLoading() {
      isContentReady = false
      pageViewController.view.alpha = 0.05
      loadingIndicator?.startAnimating()
    }

    private func showChapterError(_ error: Error) {
      let message = CoreTextEpubError.message(for: error)
      chapterLoadFailed = true
      displayLists = []
      linkRegions = []
      viewModel.markChapterLoadFailed(currentChapterIndex)
      pageViewController.dataSource = self
      let controller = CoreTextErrorPageViewController(message: message, theme: theme)
      pageViewController.setViewControllers([controller], direction: .forward, animated: false)
      commitPage(at: 0, notify: true)
      showContent()
    }

    private func showContent() {
      isContentReady = true
      loadingIndicator?.stopAnimating()
      pageViewController.view.alpha = 1
      updateOverlayLabels()
    }

    private func reloadChapter(preservePosition: Bool = false) {
      layoutGeneration += 1
      let generation = layoutGeneration
      layoutTask?.cancel()
      layoutOperation?.cancel()
      layoutTask = nil
      layoutOperation = nil
      displayLists = []
      linkRegions = []
      chapterLoadFailed = false
      pageViewController.dataSource = nil
      showLoading()

      let chapterIndex = max(
        0, min(viewModel.targetChapterIndex ?? viewModel.currentChapterIndex, viewModel.chapterCount - 1))
      currentChapterIndex = chapterIndex
      currentPageIndex = max(0, viewModel.targetPageIndex ?? viewModel.currentPageIndex)
      restoreProgression = viewModel.initialProgression(for: chapterIndex)
      if restoreProgression == nil && preservePosition && viewModel.targetPageIndex == nil {
        let pageCount = viewModel.chapterPageCount(at: chapterIndex) ?? 0
        if pageCount > 0 {
          restoreProgression = Double(currentPageIndex) / Double(pageCount)
        }
      }

      guard let chapterURL = viewModel.chapterURL(at: chapterIndex), let rootURL = viewModel.resourceRootURL else {
        if viewModel.isLoading || !viewModel.hasContent {
          showLoading()
        } else {
          showChapterError(AppErrorType.missingRequiredData(message: "Missing EPUB chapter resources."))
        }
        return
      }

      layoutTask = Task { [weak self] in
        guard let self else { return }
        do {
          let measuredViewportSize = self.pageViewController.view.bounds.size
          let viewportSize =
            measuredViewportSize.width > 0 && measuredViewportSize.height > 0
            ? measuredViewportSize
            : self.viewModel.resolvedViewportSize ?? self.view.bounds.size
          let operation = try CoreTextEpubLayoutOperation(
            rootURL: rootURL,
            chapterURL: chapterURL,
            preferences: self.preferences,
            theme: self.theme,
            viewportSize: viewportSize,
            publicationLanguage: self.viewModel.publicationLanguage,
            publicationReadingProgression: self.viewModel.publicationReadingProgression,
            generation: generation
          )
          self.layoutOperation = operation
          let session = try operation.makePageSession()
          try await session.finish()
          guard generation == self.layoutGeneration else { return }

          let sourceText = session.sourceText
          let anchors = session.pipelineLinkAnchors
          let pages = session.completedPages.map { page in
            DisplayListBuilder.build(for: page, sourceText: sourceText)
          }
          let regions = pages.map {
            LinkInteractionRegionSet.build(from: $0, spineIndex: chapterIndex, anchors: anchors)
          }
          guard !pages.isEmpty else {
            throw AppErrorType.noRenderablePages
          }
          self.displayLists = pages
          self.linkRegions = regions
          self.layoutOperation = nil
          self.viewModel.updateChapterPageCount(pages.count, for: chapterIndex)
          self.installInitialPage()
        } catch {
          guard generation == self.layoutGeneration else { return }
          if case HTMLLayoutError.cancelled = error { return }
          if error is CancellationError { return }
          self.showChapterError(error)
        }
      }
    }

    private func installInitialPage() {
      let pageCount = displayLists.count
      let requestedPage: Int
      if viewModel.targetPageIndex == -1 {
        requestedPage = pageCount - 1
      } else if let progression = restoreProgression {
        requestedPage = Int(floor(Double(pageCount) * progression))
      } else {
        requestedPage = currentPageIndex
      }
      let pageIndex = max(0, min(pageCount - 1, requestedPage))
      currentPageIndex = pageIndex
      restoreProgression = nil
      pageViewController.dataSource = self
      let controller = makePageController(at: pageIndex)
      pageViewController.setViewControllers([controller], direction: .forward, animated: false)
      commitPage(at: pageIndex, notify: true)
      showContent()
    }

    private func navigateToTargetIfNeeded() {
      guard isContentReady else { return }
      let targetChapter = viewModel.targetChapterIndex ?? currentChapterIndex
      if targetChapter != currentChapterIndex {
        reloadChapter(preservePosition: true)
        return
      }
      if chapterLoadFailed {
        viewModel.targetChapterIndex = nil
        viewModel.targetPageIndex = nil
        return
      }
      guard !displayLists.isEmpty, let targetPage = viewModel.targetPageIndex else { return }
      let pageIndex = targetPage < 0 ? displayLists.count - 1 : max(0, min(targetPage, displayLists.count - 1))
      if pageIndex != currentPageIndex {
        showPage(at: pageIndex, animated: animatePageTransitions)
      } else {
        viewModel.targetChapterIndex = nil
        viewModel.targetPageIndex = nil
      }
    }

    private func showPage(at pageIndex: Int, animated: Bool) {
      guard displayLists.indices.contains(pageIndex) else { return }
      let direction: UIPageViewController.NavigationDirection
      if pageIndex > currentPageIndex {
        direction = paginationLayout.usesReverseScrollLeft ? .reverse : .forward
      } else {
        direction = paginationLayout.usesReverseScrollLeft ? .forward : .reverse
      }
      pendingPageCommitIndex = pageIndex
      pageViewController.setViewControllers(
        [makePageController(at: pageIndex)],
        direction: direction,
        animated: animated
      ) { [weak self] completed in
        guard completed else { return }
        self?.commitPage(at: pageIndex, notify: true)
      }
    }

    private func commitPage(at pageIndex: Int, notify: Bool) {
      pendingPageCommitIndex = nil
      currentPageIndex = pageIndex
      viewModel.currentChapterIndex = currentChapterIndex
      viewModel.currentPageIndex = pageIndex
      viewModel.targetChapterIndex = nil
      viewModel.targetPageIndex = nil
      if notify {
        viewModel.pageDidChange()
      }
      updateOverlayLabels()
    }

    private func makePageController(at pageIndex: Int) -> CoreTextPageViewController {
      CoreTextPageViewController(
        pageIndex: pageIndex,
        displayList: displayLists[pageIndex],
        linkRegions: linkRegions[pageIndex],
        theme: theme
      )
    }

    private func updateOverlayLabels() {
      let location = viewModel.pageLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)
      let chapterProgress = location.flatMap {
        $0.pageCount > 0 ? Double($0.pageIndex + 1) / Double($0.pageCount) : nil
      }
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .paged,
        bookTitle: bookTitle,
        chapterTitle: location?.title,
        totalProgression: location.flatMap {
          viewModel.totalProgression(location: $0, chapterProgress: chapterProgress)
        },
        currentPageIndex: currentPageIndex,
        totalPagesInChapter: displayedPageCount,
        showingControls: showingControls,
        isRTL: viewModel.publicationReadingProgression == .rtl,
        overlayPreferences: overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard isContentReady else { return }
      let location = recognizer.location(in: view)
      let contentLocation = recognizer.location(in: pageViewController.view)
      if linkRegions.indices.contains(currentPageIndex),
        let region = linkRegions[currentPageIndex].hitTest(contentLocation),
        let chapterURL = viewModel.chapterURL(at: currentChapterIndex),
        let url = URL(string: region.href, relativeTo: chapterURL)
      {
        viewModel.navigateToURL(url)
        return
      }

      let size = view.bounds.size
      guard size.width > 0, size.height > 0 else { return }
      let action = TapZoneHelper.action(
        normalizedX: location.x / size.width,
        normalizedY: location.y / size.height,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode,
        readingDirection: readingDirection
      )
      switch action {
      case .previous:
        navigateStep(offset: -1)
      case .next:
        navigateStep(offset: 1)
      case .toggleControls:
        onCenterTap()
      }
    }

    private var readingDirection: ReadingDirection {
      switch viewModel.publicationReadingProgression {
      case .rtl:
        return .rtl
      case .ttb, .btt:
        return .vertical
      case .ltr, .auto, .none:
        return .ltr
      }
    }

    private func navigateStep(offset: Int) {
      let target = currentPageIndex + offset
      if displayLists.indices.contains(target) {
        showPage(at: target, animated: animatePageTransitions)
        return
      }
      let targetChapter = currentChapterIndex + offset
      if viewModel.chapterCount > targetChapter, targetChapter >= 0 {
        viewModel.targetChapterIndex = targetChapter
        viewModel.targetPageIndex = offset > 0 ? 0 : -1
        reloadChapter(preservePosition: true)
      } else if offset > 0 {
        onEndReached()
      }
    }

    func scrollViewWillEndDragging(
      _ scrollView: UIScrollView,
      withVelocity velocity: CGPoint,
      targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
      guard displayedPageCount > 0 else { return }
      let isFirst = currentPageIndex == 0
      let isLast = currentPageIndex == displayedPageCount - 1
      guard isFirst || isLast else { return }
      let threshold: CGFloat = 450
      if paginationLayout.reversesHorizontalGestureDirection {
        if isFirst && velocity.x < -threshold {
          navigateStep(offset: -1)
        } else if isLast && velocity.x > threshold {
          navigateStep(offset: 1)
        }
      } else {
        if isFirst && velocity.x > threshold {
          navigateStep(offset: -1)
        } else if isLast && velocity.x < -threshold {
          navigateStep(offset: 1)
        }
      }
    }

    func pageViewController(
      _ pageViewController: UIPageViewController,
      viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
      guard let pageController = viewController as? CoreTextPageViewController,
        pageController.pageIndex > 0
      else {
        return nil
      }
      return makePageController(at: pageController.pageIndex - 1)
    }

    func pageViewController(
      _ pageViewController: UIPageViewController,
      viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
      guard let pageController = viewController as? CoreTextPageViewController,
        pageController.pageIndex + 1 < displayLists.count
      else {
        return nil
      }
      return makePageController(at: pageController.pageIndex + 1)
    }

    func pageViewController(
      _ pageViewController: UIPageViewController,
      didFinishAnimating finished: Bool,
      previousViewControllers: [UIViewController],
      transitionCompleted completed: Bool
    ) {
      guard completed,
        let pageController = pageViewController.viewControllers?.first as? CoreTextPageViewController,
        pendingPageCommitIndex != pageController.pageIndex
      else {
        return
      }
      commitPage(at: pageController.pageIndex, notify: true)
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif
