#if os(iOS) || os(tvOS)
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
        guard renderConfig.doubleTapZoomMode != .disabled else { return }

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
