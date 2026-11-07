#if os(iOS) || os(tvOS)
  import AVFoundation
  import SwiftUI
  import UIKit

  final class NativePagedPageContentView: UIView, UIGestureRecognizerDelegate, PageScrollControllerHost {
    private let contentStack: UIStackView
    private let scrollController: PageScrollController
    private var pageViews: [NativePageItem] = []

    private weak var viewModel: ReaderViewModel?
    private var currentItem: ReaderViewItem?
    private var currentPageData: [NativePageData] = []
    private var currentScreenSize: CGSize = .zero
    private var currentSplitWidePageMode: SplitWidePageMode = .auto
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageSoloActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )
    private var readingDirection: ReadingDirection = .ltr
    private var isPlaybackActive = false
    private var tracksGlobalZoomState = true
    private var isUpdatingZoomState = false
    private var lastLayoutBoundsSize: CGSize = .zero
    private var doubleTapRecognizer: UITapGestureRecognizer?

    private var scrollView: SpreadPanningScrollView {
      scrollController.scrollView
    }

    override init(frame: CGRect) {
      let contentStack = UIStackView()
      self.contentStack = contentStack
      scrollController = PageScrollController(contentView: contentStack)
      super.init(frame: frame)
      scrollController.host = self
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      resetViewportStateIfNeeded()
      updatePages()
      scrollController.updateLayout(viewportSize: bounds.size)
    }

    /// `wholeSpread` is set when `item` shows as a whole spread; its arrival
    /// edge applies only when the item changes.
    func configure(
      viewModel: ReaderViewModel,
      item: ReaderViewItem,
      wholeSpread: WholeSpreadPresentation?,
      screenSize: CGSize,
      renderConfig: ReaderRenderConfig,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      isPlaybackActive: Bool,
      tracksGlobalZoomState: Bool
    ) {
      let itemChanged = currentItem != item
      let becameActive = isPlaybackActive && (itemChanged || !self.isPlaybackActive)

      self.viewModel = viewModel
      self.currentItem = item
      self.currentScreenSize = screenSize
      self.currentSplitWidePageMode = splitWidePageMode
      self.renderConfig = renderConfig
      self.readingDirection = readingDirection
      self.isPlaybackActive = isPlaybackActive
      self.tracksGlobalZoomState = tracksGlobalZoomState
      doubleTapRecognizer?.isEnabled = !renderConfig.panelMode && renderConfig.doubleTapZoomMode.isEnabled
      scrollController.configure(viewModel: viewModel, wholeSpread: wholeSpread, itemChanged: itemChanged)
      self.currentPageData = renderedPageData(isPlaybackActive: isPlaybackActive)

      if itemChanged {
        resetZoomState()
      }

      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      backgroundColor = UIColor(renderConfig.readerBackground.color)
      contentStack.semanticContentAttribute =
        readingDirection == .rtl ? .forceRightToLeft : .forceLeftToRight

      updatePages()
      scrollController.updateLayout(viewportSize: bounds.size)
      if becameActive {
        scrollController.reportPosition()
      }
    }

    func updatePlaybackActive(_ isPlaybackActive: Bool) {
      guard self.isPlaybackActive != isPlaybackActive else { return }
      self.isPlaybackActive = isPlaybackActive
      guard viewModel != nil, currentItem != nil else { return }

      currentPageData = renderedPageData(isPlaybackActive: isPlaybackActive)
      updatePages()
      scrollController.reportPosition()
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

    var showsCommittedPage: Bool {
      isPlaybackActive
    }

    func panelEngagementPoint(at point: CGPoint) -> PanelEngagementPoint? {
      let location = convert(point, to: contentStack)
      let contentBounds = contentStack.bounds
      guard contentBounds.width > 0, contentBounds.height > 0,
        scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
      else { return nil }

      for (index, pageView) in pageViews.enumerated() where currentPageData.indices.contains(index) {
        let data = currentPageData[index]
        guard data.splitMode == .none, showsCommittedPage,
          let imageSize = displayedImageSize(for: data.pageID),
          imageSize.width > 0, imageSize.height > 0
        else { continue }
        let imageRect = pageView.convert(pageView.bounds, to: contentStack)
        guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(location) else { continue }
        let fittedRect = AVMakeRect(aspectRatio: imageSize, insideRect: imageRect)
        guard fittedRect.width > 0, fittedRect.height > 0 else { continue }
        let normalizedPoint = CGPoint(
          x: (location.x - fittedRect.minX) / fittedRect.width,
          y: (location.y - fittedRect.minY) / fittedRect.height
        )
        guard (0...1).contains(normalizedPoint.x), (0...1).contains(normalizedPoint.y) else { continue }
        return PanelEngagementPoint(
          bookId: data.pageID.bookId,
          pageNumber: data.pageID.pageNumber,
          normalizedPoint: normalizedPoint
        )
      }
      return nil
    }

    func displayedImageSize(for pageID: ReaderPageID) -> CGSize? {
      pageViews.first?.displayedImageSize(for: pageID)
    }

    private func renderedPageData(isPlaybackActive: Bool) -> [NativePageData] {
      guard let viewModel, let currentItem else { return [] }
      // A whole spread renders its page uncut, like a single page.
      return viewModel.nativePageData(
        for: scrollController.wholeSpread.map { .page(id: $0.pageID) } ?? currentItem,
        readingDirection: readingDirection,
        splitWidePageMode: currentSplitWidePageMode,
        isPlaybackActive: isPlaybackActive
      )
    }

    func resetContent(backgroundColor: UIColor? = nil) {
      viewModel = nil
      currentItem = nil
      currentPageData = []
      currentScreenSize = .zero
      isPlaybackActive = false
      tracksGlobalZoomState = true
      lastLayoutBoundsSize = .zero
      scrollController.reset()
      if let backgroundColor {
        self.backgroundColor = backgroundColor
        scrollView.backgroundColor = backgroundColor
      }
      pageViews.forEach { $0.prepareForDismantle() }
      doubleTapRecognizer = nil
      resetZoomState()
    }

    private func setupUI() {
      backgroundColor = .clear

      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      addSubview(scrollView)

      contentStack.axis = .horizontal
      contentStack.distribution = .fillEqually
      contentStack.alignment = .fill
      contentStack.spacing = 0

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])

      #if os(tvOS)
        scrollView.isScrollEnabled = false
        scrollView.panGestureRecognizer.isEnabled = false
      #else
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
        doubleTapRecognizer = doubleTap
      #endif
    }

    private func updatePages() {
      guard let viewModel else { return }
      let pages = currentPageData
      let canSoloPageFromCurrentPresentation =
        renderConfig.supportsPageSoloActions
        && pages.count == 2
        && Set(pages.map(\.pageID)).count == 2

      if pageViews.count != pages.count {
        pageViews.forEach { view in
          view.prepareForDismantle()
          view.removeFromSuperview()
        }
        pageViews = pages.map { _ in NativePageItem() }
        pageViews.forEach { contentStack.addArrangedSubview($0) }
      }

      let targetHeight = bounds.height > 0 ? bounds.height : currentScreenSize.height

      for (index, data) in pages.enumerated() {
        let image = viewModel.preloadedImage(for: data.pageID)
        pageViews[index].update(
          with: data,
          viewModel: viewModel,
          image: image,
          showPageNumber: renderConfig.showPageNumber,
          showPageShadow: renderConfig.showPageShadow,
          enableLiveText: renderConfig.enableLiveText,
          enableImageContextMenu: renderConfig.enableImageContextMenu,
          supportsPageSoloActions: renderConfig.supportsPageSoloActions,
          canSoloPageFromCurrentPresentation: canSoloPageFromCurrentPresentation,
          background: renderConfig.readerBackground,
          readingDirection: readingDirection,
          displayMode: .fit,
          targetHeight: targetHeight
        )
      }
    }

    private func resetZoomState() {
      resetScrollViewportState()

      guard tracksGlobalZoomState, let viewModel, viewModel.isZoomed else { return }
      viewModel.isZoomed = false
    }

    private func resetViewportStateIfNeeded() {
      let size = bounds.size
      guard size.width > 0, size.height > 0 else { return }
      guard size != lastLayoutBoundsSize else { return }
      lastLayoutBoundsSize = size
      resetZoomState()
    }

    private func resetScrollViewportState() {
      // Never reset the zoom scale while a pinch gesture is in flight; changing
      // the scale mid-gesture desyncs UIScrollView's gesture state and can crash
      // on iPadOS 18. Retry on the next runloop until the gesture settles.
      #if os(iOS)
        if let pinch = scrollView.pinchGestureRecognizer, pinch.state == .began || pinch.state == .changed {
          DispatchQueue.main.async { [weak self] in
            self?.resetScrollViewportState()
          }
          return
        }
      #endif
      isUpdatingZoomState = true
      scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
      scrollView.contentInset = .zero
      scrollView.contentOffset = .zero
      isUpdatingZoomState = false
      scrollController.setNeedsPlacement()
      setNeedsLayout()
    }

    // Reset this slot's scroll view to minimum scale unconditionally, independent
    // of tracksGlobalZoomState or item identity. Lets the cover coordinator clear
    // a stale scale left on a slot that was zoomed while a page transition was in
    // flight. Uses isUpdatingZoomState so it does not re-fire scrollViewDidZoom.
    // A whole spread returns to the edge it rests at.
    func forceResetZoom() {
      resetScrollViewportState()
      scrollController.updateLayout(viewportSize: bounds.size)
    }

    // MARK: - Panel mode zoom (driven by PanelZoomController via the cover coordinator)

    /// Zoom to a normalized [0,1] page-space panel rect, centered with a margin so a sliver of
    /// the neighboring panels stays visible (never cropped). The panel rect is expanded to the
    /// viewport's aspect ratio and enlarged by 1/fillFactor, then handed to UIScrollView's
    /// `zoom(to:)`, which fits and centers it — the panel lands centered with the margin using
    /// only the proven zoom path (no manual offset/inset). Lets `scrollViewDidZoom` set `isZoomed`.
    func zoomToPanelRect(_ panel: PanelRect, animated: Bool) {
      let container = CGRect(origin: .zero, size: scrollView.bounds.size)
      guard container.width > 0, container.height > 0 else { return }
      let fitted = fittedImageRect(in: container)
      let panelRect = CGRect(
        x: fitted.minX + panel.x * fitted.width,
        y: fitted.minY + panel.y * fitted.height,
        width: max(panel.width * fitted.width, 1),
        height: max(panel.height * fitted.height, 1)
      )

      // Expand to the viewport aspect ratio (centered on the panel), enlarged by the fill
      // factor so the panel fills ~90% and the rest shows neighbor context. zoom(to:) fits
      // and centers this rect, so the panel ends up centered with the margin.
      let aspect = container.width / container.height
      var w = panelRect.width / PanelZoomTuning.fillFactor
      var h = panelRect.height / PanelZoomTuning.fillFactor
      if w / h > aspect { h = w / aspect } else { w = h * aspect }

      // Cap the per-step zoom (separate from the pinch-zoom max): if filling this small a panel
      // would zoom past maxStepZoom, grow the target so it just hits the cap — the panel fills a
      // bit less and shows more context, instead of an over-magnified, soft crop.
      let minTargetW = container.width / PanelZoomTuning.maxStepZoom
      let minTargetH = container.height / PanelZoomTuning.maxStepZoom
      if w < minTargetW || h < minTargetH {
        let grow = max(minTargetW / w, minTargetH / h)
        w *= grow
        h *= grow
      }

      let target = CGRect(
        x: panelRect.midX - w / 2,
        y: panelRect.midY - h / 2,
        width: w,
        height: h
      )

      // Slack on every side so zoom(to:) can CENTER panels sitting against the page edge (and
      // full-width panels) — showing a little background past the page instead of clamping the
      // panel to the screen edge. Tightened to the landed position right after the zoom (else it
      // doubles as pannable range); cleared on disengage (resetScrollViewportState / Fit).
      scrollView.contentInset = UIEdgeInsets(
        top: container.height, left: container.width,
        bottom: container.height, right: container.width
      )

      if animated {
        // Drive a non-animated zoom inside an explicit block so the step uses the tunable
        // PanelZoomTuning.stepDuration instead of UIScrollView's fixed ~0.3s.
        UIView.animate(
          withDuration: PanelZoomTuning.stepDuration,
          delay: 0,
          options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
          self.scrollView.zoom(to: target, animated: false)
          self.clampPanelPanRange()
        }
      } else {
        scrollView.zoom(to: target, animated: false)
        clampPanelPanRange()
      }
    }

    /// Shrink the oversized centering inset to exactly the overhang the landed zoom position
    /// uses. The full-viewport slack above exists only so `zoom(to:)` can center edge-hugging
    /// panels; left in place it also becomes pannable range, letting the page drag a whole
    /// screen out of bounds in every direction while engaged. Clamped to the landed overhang,
    /// panning matches the plain double-tap zoom guard: an interior panel pans strictly within
    /// the page content, an edge panel can expose only the margin its centering already shows.
    private func clampPanelPanRange() {
      scrollView.layoutIfNeeded()
      let offset = scrollView.contentOffset
      let viewport = scrollView.bounds.size
      let content = scrollView.contentSize
      scrollView.contentInset = UIEdgeInsets(
        top: max(0, -offset.y),
        left: max(0, -offset.x),
        bottom: max(0, offset.y + viewport.height - content.height),
        right: max(0, offset.x + viewport.width - content.width)
      )
    }

    /// Reset back to the whole, fitted page. Clears the panel-walk zoom AND the centering
    /// inset/offset — a full-width panel sits at min zoom but is still inset-shifted, so a
    /// plain zoomScale check would miss it.
    func resetPanelZoomToFit(animated: Bool, completion: (() -> Void)? = nil) {
      let atRest =
        scrollView.zoomScale == scrollView.minimumZoomScale
        && scrollView.contentInset == .zero
        && scrollView.contentOffset == .zero
      guard !atRest else {
        completion?()
        return
      }
      if animated {
        UIView.animate(
          withDuration: PanelZoomTuning.stepDuration,
          delay: 0,
          options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
          self.scrollView.contentInset = .zero
          self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: false)
          self.scrollView.contentOffset = .zero
        } completion: { _ in
          if self.tracksGlobalZoomState, let viewModel = self.viewModel {
            viewModel.isZoomed = false
          }
          completion?()
        }
      } else {
        forceResetZoom()
        completion?()
        if tracksGlobalZoomState, let viewModel, viewModel.isZoomed {
          viewModel.isZoomed = false
        }
      }
    }

    private func fittedImageRect(in container: CGRect) -> CGRect {
      guard let imageSize = currentDisplayedImageSize(),
        imageSize.width > 0, imageSize.height > 0
      else {
        return container
      }
      return AVMakeRect(aspectRatio: imageSize, insideRect: container)
    }

    private func currentDisplayedImageSize() -> CGSize? {
      guard let data = currentPageData.first else { return nil }
      return displayedImageSize(for: data.pageID)
    }

    func pageScrollControllerDidZoom(_ controller: PageScrollController) {
      guard tracksGlobalZoomState else { return }
      guard !isUpdatingZoomState else { return }
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

    #if os(iOS) || os(macOS)
      @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard renderConfig.doubleTapZoomMode.isEnabled else { return }

        if scrollView.zoomScale > (scrollView.minimumZoomScale + 0.01) {
          scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
          return
        }

        let targetScale = min(
          CGFloat(renderConfig.doubleTapZoomScale),
          scrollView.maximumZoomScale
        )
        let center = gesture.location(in: contentStack)
        let width = scrollView.frame.size.width / targetScale
        let height = scrollView.frame.size.height / targetScale
        let rect = CGRect(
          x: center.x - width / 2,
          y: center.y - height / 2,
          width: width,
          height: height
        )
        scrollView.zoom(to: rect, animated: true)
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
      ) -> Bool {
        if let view = touch.view, view is UIControl {
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
    #endif
  }
#endif
