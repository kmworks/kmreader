#if os(iOS)
  import UIKit

  @MainActor
  final class EpubPageViewController: UIViewController {
    private let renderingEngine: EpubRenderingEngine
    private var configuration: EpubChapterConfiguration
    private var renderer: EpubPageRenderer?
    private(set) var navigationID = UUID()
    var navigationIsCurrent: ((UUID) -> Bool)?

    var isNavigationCurrent: Bool {
      navigationIsCurrent?(navigationID) == true
    }

    func acceptsNavigation(_ navigationID: UUID) -> Bool {
      self.navigationID == navigationID && navigationIsCurrent?(navigationID) == true
    }

    private(set) var destination: EpubNavigationDestination

    func prepareNavigation(_ request: EpubNavigationRequest) {
      guard navigationID != request.id else { return }
      navigationID = request.id
      destination = request.destination
      renderer?.prepareNavigation()
    }

    func prepareInteractiveDestination(_ destination: EpubNavigationDestination) {
      self.destination = destination
    }

    func finishInteractiveNavigation() {
      guard layout.pageCount != nil else { return }
      destination = .page(currentSubPageIndex)
    }

    private func reportLanding(resolvedAnchor: String? = nil) {
      guard isNavigationCurrent, layout.pageCount != nil else { return }
      onPositionSettled?(
        EpubPageLanding(
          chapterIndex: chapterIndex, pageIndex: currentSubPageIndex,
          layout: layout, navigationID: navigationID, resolvedAnchor: resolvedAnchor
        ))
    }
    var currentSubPageIndex: Int
    var totalPagesInChapter: Int
    private var lastLayoutSize: CGSize = .zero
    private var onPageCountReady: ((Int) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    // The view model retains a link command until the resolved landing is acknowledged.
    var requiresFullExtentProvider: ((Int) -> Bool)?
    var pendingAnchorProvider: ((Int) -> EpubAnchorNavigation?)?
    var onPositionSettled: ((EpubPageLanding) -> Void)?
    var onPaginationReady: (() -> Void)?
    var onChapterLoadFailed: (() -> Void)?
    // Fires when pagination re-runs on changed geometry (appearance or viewport
    // size), so page-index-keyed snapshots cached by the coordinator go stale.
    var onRepagination: (() -> Void)?

    var chapterIndex: Int { configuration.chapterIndex }
    private(set) var layout: EpubPageLayout = .loading
    var hasPaginated: Bool { layout.isContent }

    var isContentLoaded: Bool { renderer?.isContentLoaded ?? false }

    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?
    private var loadingIndicator: UIActivityIndicatorView?
    private var containerView: UIView?
    private var containerConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?

    init(
      configuration: EpubChapterConfiguration,
      renderingEngine: EpubRenderingEngine,
      onPageCountReady: ((Int) -> Void)?
    ) {
      self.configuration = configuration
      self.destination = .page(configuration.subPageIndex)
      self.renderingEngine = renderingEngine
      self.currentSubPageIndex = configuration.subPageIndex
      self.totalPagesInChapter = configuration.totalPages
      self.onPageCountReady = onPageCountReady
      self.onLinkTap = nil
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      setupRenderer()
      setupOverlayLabels()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAppDidBecomeActive),
        name: UIApplication.didBecomeActiveNotification,
        object: nil
      )
      loadContentIfNeeded(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      // Pagination re-runs on size changes in viewDidLayoutSubviews; appearance
      // fires on every page turn.
      updateOverlayLabels()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      let contentSize = renderer?.contentView.bounds.size ?? .zero
      if contentSize.width > 0 && contentSize.height > 0,
        contentSize != lastLayoutSize || renderer?.refreshesWhenAppearingWithSameGeometry == true
      {
        lastLayoutSize = contentSize
        onRepagination?()
        refreshDisplay()
      }
    }

    @objc private func handleAppDidBecomeActive() {
      refreshDisplay()
      updateOverlayLabels()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = view.bounds.size
      let contentSize = renderer?.contentView.bounds.size ?? .zero
      guard size.width > 0, size.height > 0 else { return }

      if contentSize != lastLayoutSize {
        lastLayoutSize = contentSize
        if contentSize.width > 0 && contentSize.height > 0 {
          onRepagination?()
          refreshDisplay()
          updateOverlayLabels()
        }
      }
    }

    func configure(
      _ configuration: EpubChapterConfiguration,
      onPageCountReady: ((Int) -> Void)?
    ) {
      let shouldReload =
        configuration.chapterURL != self.configuration.chapterURL
        || configuration.chapterMediaType != self.configuration.chapterMediaType
        || configuration.rootURL != self.configuration.rootURL
        || configuration.mediaTypesByRelativePath != self.configuration.mediaTypesByRelativePath
      let appearanceChanged =
        configuration.preferences != self.configuration.preferences
        || configuration.theme != self.configuration.theme
        || configuration.containerInsets != self.configuration.containerInsets
        || configuration.contentCSS != self.configuration.contentCSS
        || configuration.readiumProperties != self.configuration.readiumProperties
        || configuration.publicationLanguage != self.configuration.publicationLanguage
        || configuration.publicationReadingProgression != self.configuration.publicationReadingProgression
        || configuration.labelTopOffset != self.configuration.labelTopOffset
        || configuration.labelBottomOffset != self.configuration.labelBottomOffset
        || configuration.useSafeArea != self.configuration.useSafeArea

      // Reset layout size when chapter changes to ensure proper size detection
      if configuration.chapterIndex != self.configuration.chapterIndex {
        lastLayoutSize = .zero
      }

      self.configuration = configuration
      totalPagesInChapter = configuration.totalPages
      self.onPageCountReady = onPageCountReady
      renderer?.configure(configuration)

      guard isViewLoaded else { return }
      updateOverlayLabels()
      if appearanceChanged {
        applyContainerInsets()
        onRepagination?()
      }

      applyTheme()
      if shouldReload || (appearanceChanged && renderer?.reloadsOnAppearanceChange == true) {
        loadContentIfNeeded(force: true)
      } else if appearanceChanged {
        applyPagination(scrollToPage: currentSubPageIndex)
      } else {
        if isContentLoaded {
          scrollToPage(currentSubPageIndex)
        }
      }
    }

    func refreshDisplay() {
      applyPagination(scrollToPage: currentSubPageIndex)
    }

    private var topAnchor: NSLayoutYAxisAnchor {
      configuration.useSafeArea ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor
    }
    private var bottomAnchor: NSLayoutYAxisAnchor {
      configuration.useSafeArea ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor
    }
    private var leadingAnchor: NSLayoutXAxisAnchor {
      configuration.useSafeArea ? view.safeAreaLayoutGuide.leadingAnchor : view.leadingAnchor
    }
    private var trailingAnchor: NSLayoutXAxisAnchor {
      configuration.useSafeArea ? view.safeAreaLayoutGuide.trailingAnchor : view.trailingAnchor
    }

    func setupOverlayLabels() {
      infoOverlay = WebPubInfoOverlaySupport.UIKitOverlay(
        containerView: view,
        topAnchor: topAnchor,
        bottomAnchor: bottomAnchor,
        topOffset: configuration.labelTopOffset,
        bottomOffset: configuration.labelBottomOffset,
        theme: configuration.theme
      )
    }

    func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .paged,
        bookTitle: configuration.bookTitle,
        chapterTitle: configuration.chapterTitle,
        totalProgression: configuration.totalProgression,
        currentPageIndex: currentSubPageIndex,
        totalPagesInChapter: totalPagesInChapter,
        showingControls: configuration.showingControls,
        isRTL: configuration.publicationReadingProgression == .rtl,
        overlayPreferences: configuration.overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    func forceEnsureContentLoaded() {
      loadContentIfNeeded(force: renderer?.forcesReloadWhenEnsured ?? false)
    }

    func makeBacksideSnapshotImage() -> UIImage? {
      guard isViewLoaded else { return nil }
      guard isContentLoaded else { return nil }
      // A mid-pagination capture would record the page while it is still hidden.
      guard let contentView = renderer?.contentView, contentView.alpha >= 0.1 else { return nil }
      // Forcing a commit from a detached controller can throw during UIKit's temporary-window move.
      guard view.window != nil else { return nil }
      view.layoutIfNeeded()
      renderer?.prepareForSnapshot()
      let bounds = view.bounds
      guard bounds.width > 1, bounds.height > 1 else { return nil }

      let format = UIGraphicsImageRendererFormat.preferred()
      format.opaque = false
      // Half scale: the backside is mirrored and only exposed while the curl is moving.
      format.scale = (view.window?.screen.scale ?? UIScreen.main.scale) / 2
      let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
      return renderer.image { _ in
        // drawHierarchy goes through the render server, so WKWebView content is
        // captured reliably; layer.render can produce blank images offscreen.
        // Forcing a commit keeps the frame current when the view is fully
        // covered and its latest scroll has not been composited yet.
        view.drawHierarchy(in: bounds, afterScreenUpdates: true)
      }
    }

    private func setupContentContainer() -> UIView {
      view.backgroundColor = configuration.theme.uiColorBackground
      let container = UIView()
      container.backgroundColor = .clear
      view.addSubview(container)
      container.translatesAutoresizingMaskIntoConstraints = false

      let insets = configuration.containerInsets
      let top = container.topAnchor.constraint(equalTo: topAnchor, constant: insets.top)
      let leading = container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left)
      let trailing = trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: insets.right)
      let bottom = bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: insets.bottom)
      containerConstraints = (top, leading, trailing, bottom)
      NSLayoutConstraint.activate([top, leading, trailing, bottom])
      containerView = container
      applyContainerInsets()

      let indicator = UIActivityIndicatorView(style: .medium)
      indicator.color = configuration.theme.uiColorText
      indicator.hidesWhenStopped = true
      indicator.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(indicator)
      NSLayoutConstraint.activate([
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      loadingIndicator = indicator
      return container
    }

    private func setupRenderer() {
      let container = setupContentContainer()
      let renderer: EpubPageRenderer
      switch renderingEngine {
      case .webView:
        renderer = WebViewEpubPageRenderer(host: self, configuration: configuration)
      case .coreText:
        renderer = CoreTextEpubPageRenderer(host: self, configuration: configuration)
      }
      renderer.install(in: container)
      self.renderer = renderer
    }

    private func applyTheme() {
      // Background fills entire view (including safe area)
      view.backgroundColor = configuration.theme.uiColorBackground
      containerView?.backgroundColor = .clear
      renderer?.applyTheme(configuration.theme)
      loadingIndicator?.color = configuration.theme.uiColorText

      // Update overlay label colors
      infoOverlay?.apply(theme: configuration.theme)
    }

    private func applyContainerInsets() {
      guard let containerConstraints else { return }
      let insets = configuration.containerInsets
      containerConstraints.top.constant = insets.top
      containerConstraints.leading.constant = insets.left
      containerConstraints.trailing.constant = insets.right
      containerConstraints.bottom.constant = insets.bottom
      view.layoutIfNeeded()
    }

    private func loadContentIfNeeded(force: Bool) {
      renderer?.loadIfNeeded(force: force)
    }

    private func applyPagination(scrollToPage pageIndex: Int) {
      guard isViewLoaded else { return }
      renderer?.applyPagination(scrollToPage: pageIndex)
    }

    private func scrollToPage(_ pageIndex: Int, completion: (() -> Void)? = nil) {
      renderer?.scrollToPage(pageIndex, completion: completion)
    }

    func scrollToPageIndex(_ pageIndex: Int, completion: (() -> Void)? = nil) {
      rendererSetPendingPageIndex(pageIndex)
      currentSubPageIndex = pageIndex
      if isContentLoaded {
        scrollToPage(pageIndex, completion: completion)
      } else {
        completion?()
      }
      updateOverlayLabels()
    }

    // Unlike scrollToPageIndex, the completion fires only after the target page has
    // painted, so transitions that sample the live view can start safely.
    func scrollToPageIndexAndSettle(_ pageIndex: Int, completion: @escaping () -> Void) {
      rendererSetPendingPageIndex(pageIndex)
      currentSubPageIndex = pageIndex
      updateOverlayLabels()
      renderer?.scrollToPageAndSettle(pageIndex, completion: completion)
    }

    func handleLinkTap(at point: CGPoint) -> Bool {
      renderer?.handleLinkTap(at: point, in: view) ?? false
    }

    func rendererWillPaginate() {
      layout = .loading
    }

    func rendererPendingOrCurrentPageIndex() -> Int {
      destination.estimatedPageIndex(pageCount: totalPagesInChapter)
    }

    func rendererSetPendingPageIndex(_ pageIndex: Int) {
      if !destination.requiresFullExtent { destination = .page(pageIndex) }
    }

    func rendererDidFail() {
      layout = .failed
      totalPagesInChapter = 1
      currentSubPageIndex = 0
      onChapterLoadFailed?()
      reportLanding()
      updateOverlayLabels()
      onPaginationReady?()
    }

    func rendererDidFinishPagination(_ pageCount: Int) {
      guard let renderer else { return }
      let requestID = navigationID
      let generation = renderer.layoutGeneration
      layout = .content(pageCount: max(1, pageCount))
      totalPagesInChapter = max(1, pageCount)
      if isNavigationCurrent { onPageCountReady?(totalPagesInChapter) }
      let pageIndex = destination.pageIndex(pageCount: totalPagesInChapter)
      renderer.scrollToPageAndSettle(pageIndex) { [weak self] in
        guard let self, self.navigationID == requestID,
          self.renderer?.layoutGeneration == generation
        else { return }
        self.currentSubPageIndex = pageIndex
        self.reportLanding()
        self.updateOverlayLabels()
        self.applyPendingAnchor()
        self.onPaginationReady?()
      }
    }

    func applyPendingAnchor() {
      guard hasPaginated, let anchor = pendingAnchorProvider?(chapterIndex), anchor.id == navigationID else { return }
      let requestID = navigationID
      let generation = renderer?.layoutGeneration
      scrollToAnchor(anchor.anchor) { [weak self] page in
        guard let self, acceptsNavigation(requestID), renderer?.layoutGeneration == generation else { return }
        if let page {
          commitAnchorLanding(page: page, anchor: anchor.anchor)
        } else {
          scrollToPageIndex(0) { [weak self] in
            guard let self, acceptsNavigation(requestID), renderer?.layoutGeneration == generation else { return }
            commitAnchorLanding(page: 0, anchor: anchor.anchor)
          }
        }
      }
    }

    private func commitAnchorLanding(page: Int, anchor: String) {
      guard isNavigationCurrent, page >= 0, page < totalPagesInChapter else { return }
      currentSubPageIndex = page
      destination = .page(page)
      reportLanding(resolvedAnchor: anchor)
      updateOverlayLabels()
    }

    func scrollToAnchor(_ anchor: String, completion: @escaping (Int?) -> Void) {
      renderer?.scrollToAnchor(anchor, completion: completion) ?? completion(nil)
    }

    func rendererStartLoading() {
      loadingIndicator?.startAnimating()
    }

    func rendererStopLoading() {
      loadingIndicator?.stopAnimating()
    }
  }
#endif
