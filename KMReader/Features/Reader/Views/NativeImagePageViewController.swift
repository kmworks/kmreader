//
// NativeImagePageViewController.swift
//

#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor
  final class NativeImagePageViewController: UIViewController, UIScrollViewDelegate,
    UIGestureRecognizerDelegate
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

    private let scrollView = SpreadPanningScrollView()
    private let pageItem = NativePageItem()
    private var contentWidthConstraint: NSLayoutConstraint?
    private var wholeSpread: WholeSpreadPresentation?
    // Edge the whole spread keeps across viewport and content-size changes:
    // where it arrived, then wherever its latest pan settled.
    private var spreadRestingEdge: ReaderSpreadEdge = .start
    private var needsSpreadPlacement = false
    private var lastLayoutViewportSize: CGSize = .zero

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
      self.wholeSpread = wholeSpread
      self.readingDirection = readingDirection
      self.renderConfig = renderConfig
      scrollView.spreadStartsAtLeft = wholeSpread?.startsAtLeft ?? true

      if isPageChanged {
        loadTask?.cancel()
        loadTask = nil
        cancelAnimatedInlinePreparation()
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        viewModel.isZoomed = false
        hideAnimatedInlinePlayback()
        spreadRestingEdge = wholeSpread?.arrivalEdge ?? .start
        needsSpreadPlacement = true
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
      let viewportSize = view.bounds.size
      if viewportSize != lastLayoutViewportSize {
        lastLayoutViewportSize = viewportSize
        needsSpreadPlacement = true
      }
      updateWholeSpreadLayout()
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

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.delegate = self
      scrollView.minimumZoomScale = 1.0
      scrollView.maximumZoomScale = 8.0
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.contentInsetAdjustmentBehavior = .never
      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      view.addSubview(scrollView)

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: view.topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])

      pageItem.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(pageItem)

      // A whole spread widens the content past the viewport by this
      // constraint's constant, so it pans at base zoom.
      let contentWidthConstraint = pageItem.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor
      )
      self.contentWidthConstraint = contentWidthConstraint

      NSLayoutConstraint.activate([
        pageItem.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
        pageItem.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        pageItem.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        pageItem.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        contentWidthConstraint,
        pageItem.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      ])
    }

    /// Pans the whole spread to `edge` for a navigation command.
    func panWholeSpread(to edge: ReaderSpreadEdge, animated: Bool) {
      guard wholeSpread != nil, scrollView.isAtBaseZoom else { return }
      spreadRestingEdge = edge
      scrollView.panSpread(to: edge, animated: animated)
      reportWholeSpreadPosition()
    }

    /// Whether a horizontal drag would pan the whole spread rather than turn
    /// the page.
    func canPanWholeSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      wholeSpread != nil && scrollView.canPanSpread(forHorizontalDrag: translationX)
    }

    /// Reports where the whole spread rests; the engine calls it once the
    /// page becomes current, and settled pans call it on their own.
    func reportWholeSpreadPosition() {
      guard let wholeSpread, let viewModel else { return }
      viewModel.recordWholeSpreadPosition(
        pageID: wholeSpread.pageID,
        restingEdges: scrollView.restingSpreadEdges
      )
    }

    /// Sizes the content for a whole spread and places it at its resting edge
    /// whenever the page, viewport, or spread width changes.
    private func updateWholeSpreadLayout() {
      guard isViewLoaded, let contentWidthConstraint else { return }
      let viewportSize = view.bounds.size
      guard viewportSize.width > 0, viewportSize.height > 0 else { return }

      let contentWidth =
        wholeSpreadImageSize().map {
          WholeSpreadLayout.contentWidth(imageSize: $0, viewportSize: viewportSize)
        } ?? viewportSize.width
      let extraWidth = max(contentWidth - viewportSize.width, 0)
      if abs(contentWidthConstraint.constant - extraWidth) > 0.5 {
        contentWidthConstraint.constant = extraWidth
        needsSpreadPlacement = true
      }

      guard needsSpreadPlacement, scrollView.isAtBaseZoom else { return }
      needsSpreadPlacement = false
      scrollView.layoutIfNeeded()
      scrollView.placeSpread(at: spreadRestingEdge)
    }

    private func wholeSpreadImageSize() -> CGSize? {
      guard let wholeSpread, let viewModel else { return nil }
      if let size = pageItem.displayedImageSize(for: wholeSpread.pageID) {
        return size
      }
      guard let page = viewModel.readerPage(for: wholeSpread.pageID)?.page,
        let width = page.width, let height = page.height
      else {
        return nil
      }
      return viewModel.rotation.rotatedSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

    private func wholeSpreadPanDidSettle() {
      scrollView.clearPendingSpreadPan()
      guard wholeSpread != nil, scrollView.isAtBaseZoom else { return }
      spreadRestingEdge = scrollView.nearestSpreadEdge
      reportWholeSpreadPosition()
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
      updateWholeSpreadLayout()

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

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      pageItem
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      self.scrollView.clearPendingSpreadPan()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate {
        wholeSpreadPanDidSettle()
      }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      wholeSpreadPanDidSettle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
      wholeSpreadPanDidSettle()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
      wholeSpreadPanDidSettle()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
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
