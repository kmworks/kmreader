//
// NativeImagePageViewController.swift
//

#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor
  final class NativeImagePageViewController: UIViewController, UIGestureRecognizerDelegate,
    PageScrollControllerHost
  {
    private weak var viewModel: ReaderViewModel?

    private var pageID = ReaderPageID(bookId: "", pageNumber: 0)
    private var splitMode: PageSplitMode = .none
    private var alignment: HorizontalAlignment = .center
    private var readingDirection: ReadingDirection = .ltr
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageIsolationActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )

    private let pageItem = NativePageItem()
    private lazy var scrollController: PageScrollController = {
      let controller = PageScrollController(contentView: pageItem)
      controller.host = self
      return controller
    }()

    private var scrollView: SpreadPanningScrollView {
      scrollController.scrollView
    }

    private var loadTask: Task<Void, Never>?
    private var animatedInlinePreparationTask: Task<Void, Never>?

    private var lastConfiguredPageID: ReaderPageID?
    private var isVisibleForAnimatedInlinePlayback = false

    /// `wholeSpread` is set when the page shows as a whole spread; its
    /// arrival edge applies only when the page changes.
    func configure(
      viewModel: ReaderViewModel,
      pageID: ReaderPageID,
      splitMode: PageSplitMode,
      alignment: HorizontalAlignment = .center,
      wholeSpread: WholeSpreadPresentation? = nil,
      readingDirection: ReadingDirection,
      renderConfig: ReaderRenderConfig
    ) {
      let isPageChanged = lastConfiguredPageID != pageID

      self.viewModel = viewModel
      self.pageID = pageID
      self.splitMode = splitMode
      self.alignment = alignment
      self.readingDirection = readingDirection
      self.renderConfig = renderConfig
      scrollController.configure(viewModel: viewModel, wholeSpread: wholeSpread, itemChanged: isPageChanged)

      if isPageChanged {
        loadTask?.cancel()
        loadTask = nil
        cancelAnimatedInlinePreparation()
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        viewModel.isZoomed = false
        hideAnimatedInlinePlayback()
      }
      lastConfiguredPageID = pageID

      if isViewLoaded {
        applyConfiguration()
      }
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      setupUI()
      setupGestures()
      applyConfiguration()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      scrollController.updateLayout(viewportSize: view.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      guard !isVisibleForAnimatedInlinePlayback else { return }
      isVisibleForAnimatedInlinePlayback = true
      refreshPageItem()
      prepareAnimatedInlinePlaybackIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      guard isVisibleForAnimatedInlinePlayback else { return }
      isVisibleForAnimatedInlinePlayback = false
      cancelAnimatedInlinePreparation()
      hideAnimatedInlinePlayback()
    }

    deinit {
      loadTask?.cancel()
      animatedInlinePreparationTask?.cancel()
    }

    private func setupUI() {
      view.backgroundColor = UIColor(renderConfig.readerBackground.color)

      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      view.addSubview(scrollView)

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: view.topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }

    /// Pans the whole spread to `edge` for a navigation command.
    func panWholeSpread(to edge: ReaderSpreadEdge, animated: Bool) {
      scrollController.panSpread(to: edge, animated: animated)
    }

    /// Whether a horizontal drag would pan the whole spread rather than turn
    /// the page.
    func canPanWholeSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      scrollController.canPanSpread(forHorizontalDrag: translationX)
    }

    /// Reports where the whole spread rests; the engine calls it once the
    /// page becomes current.
    func reportWholeSpreadPosition() {
      scrollController.reportPosition()
    }

    var showsCommittedPage: Bool {
      viewModel?.currentViewItem()?.pageIDs.contains(pageID) == true
    }

    func displayedImageSize(for pageID: ReaderPageID) -> CGSize? {
      pageItem.displayedImageSize(for: pageID)
    }

    private func setupGestures() {
      let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
      doubleTap.numberOfTapsRequired = 2
      doubleTap.delegate = self
      scrollView.addGestureRecognizer(doubleTap)
    }

    private func applyConfiguration() {
      view.backgroundColor = UIColor(renderConfig.readerBackground.color)
      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      refreshPageItem()
      prepareAnimatedInlinePlaybackIfNeeded()
    }

    private func refreshPageItem() {
      guard let viewModel else { return }

      let readerPage = viewModel.readerPage(for: pageID)
      let image = viewModel.preloadedImage(for: pageID)
      let loadFailed = image == nil && viewModel.hasFailedImageLoad(for: pageID)

      let isLoading =
        loadTask != nil
        || (image == nil && readerPage != nil && !loadFailed)
      let data = NativePageData(
        pageID: pageID,
        isLoading: isLoading,
        failure: loadFailed ? viewModel.imageLoadFailure(for: pageID) : nil,
        alignment: alignment,
        splitMode: splitMode,
        rotation: viewModel.rotation
      )

      pageItem.update(
        with: data,
        viewModel: viewModel,
        image: image,
        showPageNumber: renderConfig.showPageNumber,
        showPageShadow: renderConfig.showPageShadow,
        enableLiveText: renderConfig.enableLiveText,
        enableImageContextMenu: renderConfig.enableImageContextMenu,
        supportsPageIsolationActions: renderConfig.supportsPageIsolationActions,
        canIsolatePageFromCurrentPresentation: false,
        background: renderConfig.readerBackground,
        readingDirection: readingDirection,
        displayMode: .fit,
        targetHeight: view.bounds.height
      )

      updateAnimatedInlinePlayback()
      scrollController.updateLayout(viewportSize: view.bounds.size)

      if image == nil, readerPage != nil, !loadFailed {
        startLoadingImageIfNeeded()
      }
    }

    private func startLoadingImageIfNeeded() {
      guard loadTask == nil else { return }
      guard let viewModel else { return }

      let requestedPageID = pageID

      loadTask = Task { [weak self] in
        guard let self else { return }
        _ = await viewModel.preloadImage(for: requestedPageID)
        guard !Task.isCancelled else { return }
        guard self.pageID == requestedPageID else { return }

        self.loadTask = nil
        self.refreshPageItem()
        self.prepareAnimatedInlinePlaybackIfNeeded()
      }
    }

    private func updateAnimatedInlinePlayback() {
      guard isVisibleForAnimatedInlinePlayback else {
        hideAnimatedInlinePlayback()
        return
      }
      guard let viewModel else {
        hideAnimatedInlinePlayback()
        return
      }
      guard isCurrentAnimatedInlineTarget(viewModel: viewModel) else {
        hideAnimatedInlinePlayback()
        return
      }
      guard let sourceFileURL = viewModel.animatedSourceFileURL(for: pageID) else {
        hideAnimatedInlinePlayback()
        return
      }

      startAnimatedInlinePlayback(sourceFileURL: sourceFileURL)
    }

    private func prepareAnimatedInlinePlaybackIfNeeded() {
      guard isVisibleForAnimatedInlinePlayback else { return }
      guard let viewModel else { return }
      guard isCurrentAnimatedInlineTarget(viewModel: viewModel) else {
        cancelAnimatedInlinePreparation()
        hideAnimatedInlinePlayback()
        return
      }

      guard let readerPage = viewModel.readerPage(for: pageID) else { return }
      guard readerPage.page.isAnimatedImageCandidate else { return }
      guard viewModel.shouldPrepareAnimatedPlayback(for: pageID) else { return }
      guard viewModel.animatedSourceFileURL(for: pageID) == nil else { return }
      guard animatedInlinePreparationTask == nil else { return }

      let requestedPageID = pageID
      animatedInlinePreparationTask = Task { [weak self] in
        guard let self else { return }
        guard !Task.isCancelled else { return }
        guard self.pageID == requestedPageID else { return }
        await viewModel.prepareAnimatedPagePlaybackURL(pageID: requestedPageID)
        guard !Task.isCancelled else { return }
        guard self.pageID == requestedPageID else { return }
        self.animatedInlinePreparationTask = nil
        self.refreshPageItem()
      }
    }

    private func isCurrentAnimatedInlineTarget(viewModel: ReaderViewModel) -> Bool {
      guard viewModel.rotation == .none else { return false }
      guard let currentViewItem = viewModel.currentViewItem() else {
        return false
      }
      return currentViewItem.pageIDs.contains(pageID)
    }

    private func cancelAnimatedInlinePreparation() {
      animatedInlinePreparationTask?.cancel()
      animatedInlinePreparationTask = nil
    }

    private func hideAnimatedInlinePlayback() {
      pageItem.updateAnimatedPlayback(sourceFileURL: nil)
    }

    private func startAnimatedInlinePlayback(sourceFileURL: URL) {
      pageItem.updateAnimatedPlayback(sourceFileURL: sourceFileURL)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
      guard renderConfig.doubleTapZoomMode != .disabled else { return }

      if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
      } else {
        let point = gesture.location(in: pageItem)
        let zoomRect = calculateZoomRect(
          scale: CGFloat(renderConfig.doubleTapZoomScale),
          center: point
        )
        scrollView.zoom(to: zoomRect, animated: true)
      }
    }

    func pageScrollControllerDidZoom(_ controller: PageScrollController) {
      guard let viewModel else { return }
      let zoomed = scrollView.zoomScale > (scrollView.minimumZoomScale + 0.01)
      guard viewModel.isZoomed != zoomed else { return }
      // Defer the observable write out of the zoom gesture callback; publishing
      // SwiftUI state synchronously here can crash AttributeGraph on iOS 18.
      DispatchQueue.main.async { [weak viewModel] in
        guard let viewModel, viewModel.isZoomed != zoomed else { return }
        viewModel.isZoomed = zoomed
      }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      if let touchedView = touch.view, touchedView is UIControl {
        return false
      }
      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    private func calculateZoomRect(scale: CGFloat, center: CGPoint) -> CGRect {
      let width = scrollView.frame.size.width / scale
      let height = scrollView.frame.size.height / scale
      return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
  }
#endif
