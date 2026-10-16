#if os(iOS)
  import UIKit

  @MainActor
  final class EpubPageViewController: UIViewController {
    private let renderingEngine: EpubRenderingEngine
    private var configuration: EpubChapterConfiguration
    private var renderer: EpubPageRenderer?
    var currentSubPageIndex: Int
    var totalPagesInChapter: Int
    private var lastLayoutSize: CGSize = .zero
    private var pendingPageIndex: Int?
    private var onPageCountReady: ((Int) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onPageIndexAdjusted: ((Int) -> Void)?
    var onPaginationReady: (() -> Void)?
    var onCoreTextError: ((Error) -> Void)?
    // Fires when pagination re-runs on changed geometry (appearance or viewport
    // size), so page-index-keyed snapshots cached by the coordinator go stale.
    var onRepagination: (() -> Void)?
    var preferLastPageOnReady = false
    var targetProgressionOnReady: Double?

    var chapterIndex: Int { configuration.chapterIndex }
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
      if targetProgressionOnReady == nil && !preferLastPageOnReady {
        currentSubPageIndex = configuration.subPageIndex
      }
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
      } else if appearanceChanged || preferLastPageOnReady {
        applyPagination(scrollToPage: currentSubPageIndex)
      } else {
        if isContentLoaded {
          scrollToPage(currentSubPageIndex)
        } else {
          pendingPageIndex = currentSubPageIndex
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
      currentSubPageIndex = pageIndex
      if isContentLoaded {
        scrollToPage(pageIndex, completion: completion)
      } else {
        pendingPageIndex = pageIndex
        completion?()
      }
      updateOverlayLabels()
    }

    // Unlike scrollToPageIndex, the completion fires only after the target page has
    // painted, so transitions that sample the live view can start safely.
    func scrollToPageIndexAndSettle(_ pageIndex: Int, completion: @escaping () -> Void) {
      currentSubPageIndex = pageIndex
      updateOverlayLabels()
      renderer?.scrollToPageAndSettle(pageIndex, completion: completion)
    }

    func handleLinkTap(at point: CGPoint) -> Bool {
      renderer?.handleLinkTap(at: point, in: view) ?? false
    }

    func rendererPrepareForReload() {
      pendingPageIndex = currentSubPageIndex
    }

    func rendererPendingOrCurrentPageIndex() -> Int {
      pendingPageIndex ?? currentSubPageIndex
    }

    func rendererSetPendingPageIndex(_ pageIndex: Int) {
      pendingPageIndex = pageIndex
    }

    func rendererConsumePendingPageIndex() {
      pendingPageIndex = nil
    }

    func rendererDidProducePageCount(_ pageCount: Int) {
      totalPagesInChapter = pageCount
      onPageCountReady?(pageCount)
    }

    func rendererStartLoading() {
      loadingIndicator?.startAnimating()
    }

    func rendererStopLoading() {
      loadingIndicator?.stopAnimating()
    }
  }
#endif
