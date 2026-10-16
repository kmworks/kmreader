#if os(iOS)
  import SwiftUI
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextScrolledEpubViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let viewModel: EpubReaderViewModel
    private var preferences: EpubThemePreferences
    private var colorScheme: ColorScheme
    private var tapScrollPercentage: Double
    private var animateTapTurns: Bool
    private var overlayPreferences: EpubOverlayPreferences
    private var showingControls: Bool
    private var bookTitle: String?
    private var onCenterTap: () -> Void
    private var onEndReached: () -> Void
    private var onClose: () -> Void
    private var tapZoneMode: TapZoneMode
    private var tapZoneInversionMode: TapZoneInversionMode

    private var scrollView: UIScrollView!
    private var documentView: CoreTextContinuousDocumentView!
    private var document: BrowserScrollDocument?
    private var linkRegions: LinkInteractionRegionSet?
    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?
    private var statusHost: UIViewController?
    private var loadingIndicator: UIActivityIndicatorView?

    private var layoutTask: Task<Void, Never>?
    private var layoutOperation: CoreTextEpubLayoutOperation?
    private var layoutGeneration = 0
    private var currentChapterIndex: Int
    private var currentPageIndex: Int
    private var restoreProgression: Double?
    private var isContentReady = false
    private var lastLayoutSize: CGSize = .zero

    init(
      viewModel: EpubReaderViewModel,
      preferences: EpubThemePreferences,
      colorScheme: ColorScheme,
      tapScrollPercentage: Double,
      animateTapTurns: Bool,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      bookTitle: String?,
      onCenterTap: @escaping () -> Void,
      onEndReached: @escaping () -> Void,
      onClose: @escaping () -> Void,
      tapZoneMode: TapZoneMode,
      tapZoneInversionMode: TapZoneInversionMode
    ) {
      self.viewModel = viewModel
      self.preferences = preferences
      self.colorScheme = colorScheme
      self.tapScrollPercentage = tapScrollPercentage
      self.animateTapTurns = animateTapTurns
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.bookTitle = bookTitle
      self.onCenterTap = onCenterTap
      self.onEndReached = onEndReached
      self.onClose = onClose
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

    private var viewportHeight: CGFloat {
      max(1, scrollView?.bounds.height ?? 1)
    }

    private var maximumOffset: CGFloat {
      guard let document else { return 0 }
      return max(0, document.contentSize.height - viewportHeight)
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = theme.uiColorBackground
      setupScrollView()
      setupOverlay()
      setupGestures()
      showLoading()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = scrollView.bounds.size
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
      tapScrollPercentage: Double,
      animateTapTurns: Bool,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      bookTitle: String?,
      onCenterTap: @escaping () -> Void,
      onEndReached: @escaping () -> Void,
      onClose: @escaping () -> Void,
      tapZoneMode: TapZoneMode,
      tapZoneInversionMode: TapZoneInversionMode
    ) {
      let layoutAppearanceChanged =
        preferences != self.preferences
        || colorScheme != self.colorScheme

      self.preferences = preferences
      self.colorScheme = colorScheme
      self.tapScrollPercentage = tapScrollPercentage
      self.animateTapTurns = animateTapTurns
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.bookTitle = bookTitle
      self.onCenterTap = onCenterTap
      self.onEndReached = onEndReached
      self.onClose = onClose
      self.tapZoneMode = tapZoneMode
      self.tapZoneInversionMode = tapZoneInversionMode

      view.backgroundColor = theme.uiColorBackground
      documentView.backgroundColor = theme.uiColorBackground
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

    private func setupScrollView() {
      scrollView = UIScrollView(frame: .zero)
      scrollView.delegate = self
      scrollView.alwaysBounceVertical = true
      scrollView.showsVerticalScrollIndicator = false
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.contentInsetAdjustmentBehavior = .never
      scrollView.backgroundColor = .clear
      view.addSubview(scrollView)
      scrollView.translatesAutoresizingMaskIntoConstraints = false
      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInsets.left),
        trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: containerInsets.right),
        scrollView.topAnchor.constraint(equalTo: topAnchor, constant: containerInsets.top),
        bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: containerInsets.bottom),
      ])

      documentView = CoreTextContinuousDocumentView(frame: .zero)
      documentView.backgroundColor = theme.uiColorBackground
      scrollView.addSubview(documentView)

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
      tapRecognizer.require(toFail: scrollView.panGestureRecognizer)
      view.addGestureRecognizer(tapRecognizer)
    }

    private func showLoading() {
      isContentReady = false
      statusHost?.removeFromParent()
      statusHost?.view.removeFromSuperview()
      statusHost = nil
      scrollView.alpha = 0.05
      loadingIndicator?.startAnimating()
    }

    private func showError(_ error: Error) {
      isContentReady = false
      scrollView.alpha = 0.05
      loadingIndicator?.stopAnimating()
      statusHost?.removeFromParent()
      statusHost?.view.removeFromSuperview()
      let host = UIHostingController(
        rootView: ReaderUnavailableView(
          icon: AppIcon.loadError,
          title: "Failed to load media",
          message: CoreTextEpubError.message(for: error),
          onRetry: { [weak self] in
            self?.reloadChapter(preservePosition: true)
          },
          onClose: onClose
        )
      )
      addChild(host)
      view.addSubview(host.view)
      host.view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        host.view.topAnchor.constraint(equalTo: view.topAnchor),
        host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      host.didMove(toParent: self)
      statusHost = host
    }

    private func showContent() {
      isContentReady = true
      loadingIndicator?.stopAnimating()
      statusHost?.removeFromParent()
      statusHost?.view.removeFromSuperview()
      statusHost = nil
      scrollView.alpha = 1
      updateOverlayLabels()
    }

    private func reloadChapter(preservePosition: Bool = false) {
      layoutGeneration += 1
      let generation = layoutGeneration
      layoutTask?.cancel()
      layoutOperation?.cancel()
      layoutTask = nil
      layoutOperation = nil
      document = nil
      linkRegions = nil
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
          showError(AppErrorType.missingRequiredData(message: "Missing EPUB chapter resources."))
        }
        return
      }

      layoutTask = Task { [weak self] in
        guard let self else { return }
        do {
          let measuredViewportSize = self.scrollView.bounds.size
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
          let scrollDocument = try operation.makeContinuousDocument()
          guard generation == self.layoutGeneration else { return }
          guard scrollDocument.contentSize.height > 0 else {
            throw AppErrorType.noRenderablePages
          }
          self.document = scrollDocument
          self.linkRegions = scrollDocument.interactionRegions(spineIndex: chapterIndex)
          self.layoutOperation = nil
          self.installInitialDocument()
        } catch {
          guard generation == self.layoutGeneration else { return }
          if case HTMLLayoutError.cancelled = error { return }
          if error is CancellationError { return }
          self.showError(error)
        }
      }
    }

    private func installInitialDocument() {
      guard let document else { return }
      documentView.document = document
      documentView.frame = CGRect(origin: .zero, size: document.contentSize)
      scrollView.contentSize = document.contentSize
      scrollView.contentOffset = .zero

      let pageCount = currentPageCount
      viewModel.updateChapterPageCount(pageCount, for: currentChapterIndex)
      let requestedPage: Int
      if viewModel.targetPageIndex == -1 {
        requestedPage = pageCount - 1
      } else if let progression = restoreProgression {
        requestedPage = Int(floor(Double(pageCount) * progression))
      } else {
        requestedPage = currentPageIndex
      }
      let pageIndex = max(0, min(pageCount - 1, requestedPage))
      restoreProgression = nil
      scrollToPage(at: pageIndex, animated: false)
      showContent()
    }

    private var currentPageCount: Int {
      max(1, Int(ceil(max(1, document?.contentSize.height ?? 1) / viewportHeight)))
    }

    private func navigateToTargetIfNeeded() {
      guard isContentReady, document != nil else { return }
      let targetChapter = viewModel.targetChapterIndex ?? currentChapterIndex
      if targetChapter != currentChapterIndex {
        reloadChapter(preservePosition: true)
        return
      }
      guard let targetPage = viewModel.targetPageIndex else { return }
      let pageIndex = targetPage < 0 ? currentPageCount - 1 : max(0, min(targetPage, currentPageCount - 1))
      if pageIndex != currentPageIndex {
        scrollToPage(at: pageIndex, animated: animateTapTurns)
      } else {
        viewModel.targetChapterIndex = nil
        viewModel.targetPageIndex = nil
      }
    }

    private func scrollToPage(at pageIndex: Int, animated: Bool) {
      let clampedIndex = max(0, min(currentPageCount - 1, pageIndex))
      let targetOffset = min(maximumOffset, viewportHeight * CGFloat(clampedIndex))
      scrollToOffset(targetOffset, animated: animated)
    }

    private func scrollToOffset(_ offset: CGFloat, animated: Bool) {
      let target = min(maximumOffset, max(0, offset))
      if animated {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
          self.scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        } completion: { [weak self] _ in
          self?.updatePageFromScroll()
        }
      } else {
        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        updatePageFromScroll()
      }
    }

    private func updatePageFromScroll() {
      let pageIndex = max(0, min(currentPageCount - 1, Int(round(scrollView.contentOffset.y / viewportHeight))))
      currentPageIndex = pageIndex
      viewModel.currentChapterIndex = currentChapterIndex
      viewModel.currentPageIndex = pageIndex
      viewModel.targetChapterIndex = nil
      viewModel.targetPageIndex = nil
      viewModel.pageDidChange()
      updateOverlayLabels()
    }

    private func updateOverlayLabels() {
      let location = viewModel.pageLocation(chapterIndex: currentChapterIndex, pageIndex: currentPageIndex)
      let chapterProgress = location.flatMap {
        $0.pageCount > 0 ? Double($0.pageIndex + 1) / Double($0.pageCount) : nil
      }
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .scrolled,
        bookTitle: bookTitle,
        chapterTitle: location?.title,
        totalProgression: location.flatMap {
          viewModel.totalProgression(location: $0, chapterProgress: chapterProgress)
        },
        currentPageIndex: currentPageIndex,
        totalPagesInChapter: currentPageCount,
        showingControls: showingControls,
        isRTL: viewModel.publicationReadingProgression == .rtl,
        overlayPreferences: overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard isContentReady else { return }
      let tapLocation = recognizer.location(in: view)
      if let linkRegions,
        let region = linkRegions.hitTest(recognizer.location(in: documentView)),
        let chapterURL = viewModel.chapterURL(at: currentChapterIndex),
        let url = URL(string: region.href, relativeTo: chapterURL)
      {
        viewModel.navigateToURL(url)
        return
      }

      let size = view.bounds.size
      guard size.width > 0, size.height > 0 else { return }
      let action = TapZoneHelper.action(
        normalizedX: tapLocation.x / size.width,
        normalizedY: tapLocation.y / size.height,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode,
        readingDirection: .vertical
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

    private func navigateStep(offset: Int) {
      let step = viewportHeight * CGFloat(tapScrollPercentage / 100)
      let currentOffset = scrollView.contentOffset.y
      if offset > 0, currentOffset >= maximumOffset - 1 {
        navigateChapter(offset: 1)
        return
      }
      if offset < 0, currentOffset <= 1 {
        navigateChapter(offset: -1)
        return
      }
      scrollToOffset(currentOffset + step * CGFloat(offset), animated: animateTapTurns)
    }

    private func navigateChapter(offset: Int) {
      let targetChapter = currentChapterIndex + offset
      guard viewModel.chapterCount > targetChapter, targetChapter >= 0 else {
        if offset > 0 {
          onEndReached()
        }
        return
      }
      viewModel.targetChapterIndex = targetChapter
      viewModel.targetPageIndex = offset > 0 ? 0 : -1
      reloadChapter(preservePosition: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard isContentReady else { return }
      updatePageFromScroll()
    }

    func scrollViewWillEndDragging(
      _ scrollView: UIScrollView,
      withVelocity velocity: CGPoint,
      targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
      guard isContentReady else { return }
      let currentOffset = scrollView.contentOffset.y
      if currentOffset <= 0, velocity.y > 0.8 {
        navigateChapter(offset: -1)
      } else if currentOffset >= maximumOffset - 1, velocity.y < -0.8 {
        navigateChapter(offset: 1)
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif
