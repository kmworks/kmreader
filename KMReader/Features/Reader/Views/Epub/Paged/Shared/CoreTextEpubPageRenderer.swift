#if os(iOS)
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextEpubPageRenderer: EpubPageRenderer {
    private weak var host: EpubPageViewController?
    private var configuration: EpubChapterConfiguration
    private let displayView = CoreTextDisplayListView()
    private var displayLists: [DisplayList] = []
    private var linkRegions: [LinkInteractionRegionSet] = []
    private var layoutTask: Task<Void, Never>?
    private var layoutOperation: CoreTextEpubLayoutOperation?
    private var layoutGeneration = 0
    private var layoutSize: CGSize = .zero
    private var settleCompletions: [() -> Void] = []
    private var errorView: CoreTextChapterErrorView?
    private(set) var isContentLoaded = false

    var contentView: UIView { displayView }
    let refreshesWhenAppearingWithSameGeometry = true
    let reloadsOnAppearanceChange = true
    let forcesReloadWhenEnsured = false

    init(host: EpubPageViewController, configuration: EpubChapterConfiguration) {
      self.host = host
      self.configuration = configuration
    }

    deinit {
      layoutTask?.cancel()
      layoutOperation = nil
    }

    func install(in container: UIView) {
      displayView.alpha = 0.01
      container.addSubview(displayView)
      displayView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        displayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        displayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        displayView.topAnchor.constraint(equalTo: container.topAnchor),
        displayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
      applyTheme(configuration.theme)
    }

    func configure(_ configuration: EpubChapterConfiguration) {
      if configuration.chapterIndex != self.configuration.chapterIndex {
        layoutSize = .zero
      }
      self.configuration = configuration
    }

    func applyTheme(_ theme: ReaderTheme) {
      displayView.backgroundColor = theme.uiColorBackground
    }

    func loadIfNeeded(force: Bool) {
      guard let host, let chapterURL = configuration.chapterURL, let rootURL = configuration.rootURL else { return }
      let viewportSize = displayView.bounds.size
      guard viewportSize.width > 0, viewportSize.height > 0 else { return }

      if !force {
        if isContentLoaded && layoutSize == viewportSize {
          showPage(at: host.currentSubPageIndex)
          return
        }
        if layoutTask != nil && layoutSize == viewportSize { return }
      }

      layoutGeneration += 1
      let generation = layoutGeneration
      layoutTask?.cancel()
      layoutOperation?.cancel()
      layoutTask = nil
      layoutOperation = nil
      layoutSize = viewportSize
      displayLists = []
      linkRegions = []
      isContentLoaded = false
      host.rendererPrepareForReload()
      displayView.displayList = nil
      errorView?.removeFromSuperview()
      errorView = nil
      displayView.alpha = 0.01
      host.rendererStartLoading()

      let configuration = configuration
      layoutTask = Task { [weak self] in
        guard let self else { return }
        do {
          let operation = try CoreTextEpubLayoutOperation(
            rootURL: rootURL,
            chapterURL: chapterURL,
            preferences: configuration.preferences,
            theme: configuration.theme,
            viewportSize: viewportSize,
            publicationLanguage: configuration.publicationLanguage,
            publicationReadingProgression: configuration.publicationReadingProgression,
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
          guard !pages.isEmpty else {
            throw AppErrorType.noRenderablePages
          }
          let regions = pages.map {
            LinkInteractionRegionSet.build(from: $0, spineIndex: configuration.chapterIndex, anchors: anchors)
          }
          self.layoutTask = nil
          self.layoutOperation = nil
          self.installPages(pages, linkRegions: regions)
        } catch {
          guard generation == self.layoutGeneration else { return }
          if case HTMLLayoutError.cancelled = error { return }
          if error is CancellationError { return }
          self.layoutTask = nil
          self.layoutOperation = nil
          self.installErrorPage(CoreTextEpubError.message(for: error))
        }
      }
    }

    private func installErrorPage(_ message: String) {
      guard let host else { return }
      displayLists = []
      linkRegions = []
      let errorView = CoreTextChapterErrorView(message: message, theme: configuration.theme)
      errorView.translatesAutoresizingMaskIntoConstraints = false
      displayView.addSubview(errorView)
      NSLayoutConstraint.activate([
        errorView.leadingAnchor.constraint(equalTo: displayView.leadingAnchor),
        errorView.trailingAnchor.constraint(equalTo: displayView.trailingAnchor),
        errorView.topAnchor.constraint(equalTo: displayView.topAnchor),
        errorView.bottomAnchor.constraint(equalTo: displayView.bottomAnchor),
      ])
      self.errorView = errorView
      host.rendererDidProducePageCount(1)

      let previousPageIndex = host.currentSubPageIndex
      host.rendererConsumePendingPageIndex()
      isContentLoaded = true
      showPage(at: 0)
      if previousPageIndex != 0 {
        host.onPageIndexAdjusted?(0)
      }
      host.rendererStopLoading()
      host.onPaginationReady?()
      finishSettleCompletions()
    }

    private func installPages(_ pages: [DisplayList], linkRegions: [LinkInteractionRegionSet]) {
      guard let host else { return }
      displayLists = pages
      self.linkRegions = linkRegions
      host.rendererDidProducePageCount(pages.count)

      let previousPageIndex = host.currentSubPageIndex
      let requestedPage: Int
      if host.preferLastPageOnReady {
        requestedPage = pages.count - 1
      } else if let progression = host.targetProgressionOnReady {
        requestedPage = Int(floor(Double(pages.count) * progression))
      } else {
        requestedPage = host.rendererPendingOrCurrentPageIndex()
      }
      let pageIndex = max(0, min(pages.count - 1, requestedPage))
      host.rendererConsumePendingPageIndex()
      isContentLoaded = true
      showPage(at: pageIndex)
      if previousPageIndex != pageIndex {
        host.onPageIndexAdjusted?(pageIndex)
      }
      host.rendererStopLoading()
      host.onPaginationReady?()
      finishSettleCompletions()
    }

    private func showPage(at pageIndex: Int) {
      guard let host else { return }
      if errorView != nil {
        host.currentSubPageIndex = 0
        displayView.alpha = 1
        host.updateOverlayLabels()
        return
      }
      guard displayLists.indices.contains(pageIndex) else { return }
      host.currentSubPageIndex = pageIndex
      displayView.displayList = displayLists[pageIndex]
      displayView.layer.displayIfNeeded()
      displayView.alpha = 1
      host.updateOverlayLabels()
    }

    private func finishSettleCompletions() {
      let completions = settleCompletions
      settleCompletions.removeAll()
      for completion in completions {
        completion()
      }
    }

    func applyPagination(scrollToPage pageIndex: Int) {
      guard configuration.chapterURL != nil, configuration.rootURL != nil else { return }
      let contentSize = displayView.bounds.size
      let shouldReload = !isContentLoaded || contentSize != layoutSize
      loadIfNeeded(force: shouldReload)
      if isContentLoaded {
        showPage(at: pageIndex)
      }
    }

    func scrollToPage(_ pageIndex: Int, completion: (() -> Void)?) {
      guard isContentLoaded else {
        completion?()
        return
      }
      showPage(at: pageIndex)
      completion?()
    }

    func scrollToPageAndSettle(_ pageIndex: Int, completion: @escaping () -> Void) {
      guard let host else {
        completion()
        return
      }
      guard isContentLoaded else {
        host.rendererSetPendingPageIndex(pageIndex)
        settleCompletions.append(completion)
        if configuration.chapterURL != nil, configuration.rootURL != nil {
          loadIfNeeded(force: false)
        }
        return
      }
      showPage(at: pageIndex)
      completion()
    }

    func handleLinkTap(at point: CGPoint, in hostView: UIView) -> Bool {
      guard let host,
        displayLists.indices.contains(host.currentSubPageIndex),
        linkRegions.indices.contains(host.currentSubPageIndex),
        let chapterURL = configuration.chapterURL
      else {
        return false
      }
      let contentPoint = displayView.convert(point, from: hostView)
      guard let region = linkRegions[host.currentSubPageIndex].hitTest(contentPoint),
        let url = URL(string: region.href, relativeTo: chapterURL)
      else {
        return false
      }
      host.onLinkTap?(url)
      return true
    }

    func prepareForSnapshot() {
      displayView.layer.displayIfNeeded()
    }
  }
#endif
