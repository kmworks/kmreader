//
// WebtoonReaderView_iOS.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit

  struct WebtoonReaderView: UIViewRepresentable {
    let viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler
    let onZoomRequest: ((ReaderPageID, CGPoint) -> Void)?
    let pageWidth: CGFloat
    let renderConfig: ReaderRenderConfig
    let scrollController: WebtoonScrollController

    init(
      viewModel: ReaderViewModel,
      pageWidth: CGFloat,
      renderConfig: ReaderRenderConfig,
      readListContext: ReaderReadListContext? = nil,
      onDismiss: @escaping () -> Void = {},
      onTapZoneTap: @escaping ReaderTapZoneTapHandler,
      onZoomRequest: ((ReaderPageID, CGPoint) -> Void)? = nil,
      scrollController: WebtoonScrollController
    ) {
      self.viewModel = viewModel
      self.pageWidth = pageWidth
      self.renderConfig = renderConfig
      self.readListContext = readListContext
      self.onDismiss = onDismiss
      self.onTapZoneTap = onTapZoneTap
      self.onZoomRequest = onZoomRequest
      self.scrollController = scrollController
    }

    func makeUIView(context: Context) -> UICollectionView {
      let layout = WebtoonLayout()
      let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
      collectionView.delegate = context.coordinator
      collectionView.dataSource = context.coordinator
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      collectionView.showsVerticalScrollIndicator = false
      collectionView.showsHorizontalScrollIndicator = false
      collectionView.contentInsetAdjustmentBehavior = .never
      collectionView.bounces = false
      collectionView.scrollsToTop = false
      collectionView.isPrefetchingEnabled = false

      collectionView.register(WebtoonPageCell.self, forCellWithReuseIdentifier: "WebtoonPageCell")
      collectionView.register(
        WebtoonFooterCell.self, forCellWithReuseIdentifier: "WebtoonFooterCell")

      let doubleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDoubleTap(_:))
      )
      doubleTapGesture.numberOfTapsRequired = 2
      doubleTapGesture.cancelsTouchesInView = false
      doubleTapGesture.delegate = context.coordinator
      collectionView.addGestureRecognizer(doubleTapGesture)
      context.coordinator.doubleTapGesture = doubleTapGesture

      let singleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleSingleTap(_:))
      )
      singleTapGesture.numberOfTapsRequired = 1
      singleTapGesture.cancelsTouchesInView = false
      singleTapGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: doubleTapGesture)
      singleTapGesture.require(toFail: collectionView.panGestureRecognizer)
      collectionView.addGestureRecognizer(singleTapGesture)

      let longPressGesture = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressGesture.cancelsTouchesInView = false
      longPressGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: longPressGesture)
      collectionView.addGestureRecognizer(longPressGesture)

      let pinchGesture = UIPinchGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handlePinch(_:))
      )
      pinchGesture.delegate = context.coordinator
      collectionView.addGestureRecognizer(pinchGesture)

      context.coordinator.collectionView = collectionView
      context.coordinator.applyDoubleTapGestureState()
      scrollController.target = context.coordinator
      context.coordinator.scheduleInitialScroll()

      return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      context.coordinator.update(
        viewModel: viewModel,
        readListContext: readListContext,
        onDismiss: onDismiss,
        onTapZoneTap: onTapZoneTap,
        onZoomRequest: onZoomRequest,
        pageWidth: pageWidth,
        collectionView: collectionView,
        renderConfig: renderConfig
      )
      context.coordinator.scrollController = scrollController
      scrollController.target = context.coordinator
    }

    @MainActor
    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
      coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSource,
      UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, WebtoonScrollCommandHandling
    {
      var collectionView: UICollectionView?
      private var scrollEngine: WebtoonScrollEngine
      weak var viewModel: ReaderViewModel?
      var readListContext: ReaderReadListContext?
      var onDismiss: (() -> Void)?
      var onTapZoneTap: ReaderTapZoneTapHandler?
      var onZoomRequest: ((ReaderPageID, CGPoint) -> Void)?
      weak var scrollController: WebtoonScrollController?
      var lastPagesCount: Int = 0
      var isUserScrolling: Bool = false
      var isProgrammaticAnimatedScroll: Bool = false
      var pageWidth: CGFloat = 0
      var readerBackground: ReaderBackground = .system
      var tapZoneMode: TapZoneMode = .defaultLayout
      var tapZoneInversionMode: TapZoneInversionMode = .auto
      var doubleTapZoomMode: DoubleTapZoomMode = .enabled
      var showPageNumber: Bool = true
      var hasTriggeredZoomGesture: Bool = false
      weak var doubleTapGesture: UITapGestureRecognizer?
      private var deferredReloadWorkItem: DispatchWorkItem?
      private var deferredCleanupWorkItem: DispatchWorkItem?
      private var sizeProbeTasks: [ReaderPageID: Task<Void, Never>] = [:]
      private var pendingMeasuredPageIDs: Set<ReaderPageID> = []
      private var pagePresentationObserverToken: UUID?

      private struct ScrollAnchor {
        let pageID: ReaderPageID
        let offsetWithinPage: CGFloat
      }

      var heightCache = WebtoonPageHeightCache()

      init(_ parent: WebtoonReaderView) {
        self.scrollEngine = WebtoonScrollEngine(
          initialPageID: parent.viewModel.currentReaderPage?.id
        )
        self.viewModel = parent.viewModel
        self.readListContext = parent.readListContext
        self.onDismiss = parent.onDismiss
        self.onTapZoneTap = parent.onTapZoneTap
        self.onZoomRequest = parent.onZoomRequest
        self.scrollController = parent.scrollController
        self.lastPagesCount = parent.viewModel.pageCount
        self.pageWidth = parent.pageWidth
        self.heightCache.lastPageWidth = parent.pageWidth
        self.readerBackground = parent.renderConfig.readerBackground
        self.tapZoneMode = parent.renderConfig.tapZoneMode
        self.tapZoneInversionMode = parent.renderConfig.tapZoneInversionMode
        self.doubleTapZoomMode = parent.renderConfig.doubleTapZoomMode
        self.showPageNumber = parent.renderConfig.showPageNumber
        super.init()
        _ = scrollEngine.rebuildContentItemsIfNeeded(viewModel: viewModel)
      }

      // MARK: - Helper Methods

      private var pageCount: Int {
        viewModel?.pageCount ?? 0
      }

      private var isScrollInteractionActive: Bool {
        guard let collectionView else {
          return isUserScrolling || isProgrammaticAnimatedScroll
        }
        return isUserScrolling
          || isProgrammaticAnimatedScroll
          || collectionView.isDragging
          || collectionView.isDecelerating
          || collectionView.isTracking
      }

      private func itemIndex(forPageID pageID: ReaderPageID?) -> Int? {
        scrollEngine.itemIndex(forPageID: pageID)
      }

      private func indexPath(forPageID pageID: ReaderPageID?) -> IndexPath? {
        guard let itemIndex = itemIndex(forPageID: pageID) else { return nil }
        return IndexPath(item: itemIndex, section: 0)
      }

      private func currentAnchorPageID(preferredPageID: ReaderPageID? = nil) -> ReaderPageID? {
        preferredPageID ?? scrollEngine.currentPageID ?? viewModel?.currentReaderPage?.id
      }

      private func captureScrollAnchor(
        preferredPageID: ReaderPageID? = nil,
        in collectionView: UICollectionView
      ) -> ScrollAnchor? {
        guard scrollEngine.hasScrolledToInitialPage else { return nil }
        guard let pageID = currentAnchorPageID(preferredPageID: preferredPageID) else { return nil }
        guard let offsetWithinPage = captureOffsetWithinPage(pageID, in: collectionView) else {
          return nil
        }
        return ScrollAnchor(pageID: pageID, offsetWithinPage: offsetWithinPage)
      }

      @discardableResult
      private func restoreScrollAnchor(_ anchor: ScrollAnchor?, in collectionView: UICollectionView)
        -> Bool
      {
        guard let anchor else { return false }
        return restoreOffsetWithinPage(anchor.offsetWithinPage, for: anchor.pageID, in: collectionView)
      }

      private func currentContentPageIDs() -> Set<ReaderPageID> {
        Set(
          scrollEngine.contentItems.compactMap { item in
            guard case .page(let pageID) = item else { return nil }
            return pageID
          }
        )
      }

      private func pruneStaleMeasurementState() {
        let validPageIDs = currentContentPageIDs()
        heightCache.retainHeights(for: validPageIDs)
        pendingMeasuredPageIDs.formIntersection(validPageIDs)

        let stalePageIDs = sizeProbeTasks.keys.filter { !validPageIDs.contains($0) }
        for pageID in stalePageIDs {
          sizeProbeTasks[pageID]?.cancel()
          sizeProbeTasks.removeValue(forKey: pageID)
        }
      }

      private func hasKnownHeight(for pageID: ReaderPageID, page: BookPage?) -> Bool {
        if heightCache.hasHeight(for: pageID) {
          return true
        }

        guard let page else { return false }
        return (page.width ?? 0) > 0 && (page.height ?? 0) > 0
      }

      private func applyMeasuredHeightIfNeeded(for pageID: ReaderPageID, pixelSize: CGSize) {
        guard heightCache.updateHeight(for: pageID, pixelSize: pixelSize, pageWidth: pageWidth) else {
          return
        }
        if isScrollInteractionActive {
          pendingMeasuredPageIDs.insert(pageID)
        } else {
          invalidateLayout(for: pageID)
        }
      }

      private func invalidateLayout(for pageID: ReaderPageID) {
        guard let collectionView, let indexPath = indexPath(forPageID: pageID) else { return }
        let scrollAnchor = captureScrollAnchor(in: collectionView)

        UIView.performWithoutAnimation {
          collectionView.performBatchUpdates(
            {
              collectionView.reloadItems(at: [indexPath])
            },
            completion: { [weak self] _ in
              guard let self else { return }
              collectionView.layoutIfNeeded()
              _ = self.restoreScrollAnchor(scrollAnchor, in: collectionView)
              self.updateCurrentPage()
            })
        }
      }

      private func applyPendingMeasuredLayoutUpdatesIfNeeded() {
        guard !pendingMeasuredPageIDs.isEmpty else { return }
        guard let collectionView else { return }

        let scrollAnchor = captureScrollAnchor(in: collectionView)
        let indexPaths = pendingMeasuredPageIDs.compactMap { indexPath(forPageID: $0) }
        pendingMeasuredPageIDs.removeAll()
        guard !indexPaths.isEmpty else { return }

        UIView.performWithoutAnimation {
          collectionView.performBatchUpdates(
            {
              collectionView.reloadItems(at: indexPaths)
            },
            completion: { [weak self] _ in
              guard let self else { return }
              collectionView.layoutIfNeeded()
              if !self.restoreScrollAnchor(scrollAnchor, in: collectionView),
                let pageID = scrollAnchor?.pageID
              {
                self.requestInitialScroll(pageID, delay: WebtoonConstants.layoutReadyDelay)
              }
              self.updateCurrentPage()
            })
        }
      }

      private func ensureMeasuredHeightProbe(for pageID: ReaderPageID, page: BookPage?) {
        guard !hasKnownHeight(for: pageID, page: page) else { return }
        guard sizeProbeTasks[pageID] == nil else { return }
        guard let viewModel else { return }

        sizeProbeTasks[pageID] = Task { @MainActor [weak self, weak viewModel] in
          defer { self?.sizeProbeTasks[pageID] = nil }
          guard let self, let viewModel else { return }
          guard let fileURL = await viewModel.getPageImageFileURL(pageID: pageID) else { return }
          guard let pixelSize = ImageDecodeHelper.displayPixelSize(at: fileURL) else { return }
          self.applyMeasuredHeightIfNeeded(for: pageID, pixelSize: pixelSize)
        }
      }

      private func displayImageIfReady(
        _ image: PlatformImage?,
        for pageID: ReaderPageID,
        page: BookPage?
      ) -> PlatformImage? {
        guard let image else { return nil }
        if let pixelSize = webtoonPixelSize(from: image) {
          _ = heightCache.updateHeight(for: pageID, pixelSize: pixelSize, pageWidth: pageWidth)
        }
        return hasKnownHeight(for: pageID, page: page) ? image : nil
      }

      func scheduleInitialScroll() {
        scrollEngine.scheduleInitialScroll(
          currentPageID: scrollEngine.currentPageID,
          schedule: scheduleOnMain,
          canScrollToPageID: { [weak self] pageID in
            guard let self else { return false }
            guard self.pageCount > 0 else { return false }
            return self.itemIndex(forPageID: pageID) != nil
          },
          perform: { [weak self] pageID in self?.scrollToInitialPage(pageID) }
        )
      }

      func requestInitialScroll(_ pageID: ReaderPageID?, delay: TimeInterval) {
        scrollEngine.requestInitialScroll(
          pageID,
          delay: delay,
          schedule: scheduleOnMain,
          canScrollToPageID: { [weak self] targetPageID in
            guard let self else { return false }
            guard self.pageCount > 0 else { return false }
            return self.itemIndex(forPageID: targetPageID) != nil
          },
          perform: { [weak self] targetPageID in self?.scrollToInitialPage(targetPageID) }
        )
      }

      func update(
        viewModel: ReaderViewModel,
        readListContext: ReaderReadListContext?,
        onDismiss: @escaping () -> Void,
        onTapZoneTap: @escaping ReaderTapZoneTapHandler,
        onZoomRequest: ((ReaderPageID, CGPoint) -> Void)?,
        pageWidth: CGFloat,
        collectionView: UICollectionView,
        renderConfig: ReaderRenderConfig
      ) {
        resetContentInsetsIfNeeded(for: collectionView)
        self.viewModel = viewModel
        updateViewModelObservation(viewModel)
        self.readListContext = readListContext
        self.onDismiss = onDismiss
        self.onTapZoneTap = onTapZoneTap
        self.onZoomRequest = onZoomRequest
        self.pageWidth = pageWidth
        self.readerBackground = renderConfig.readerBackground
        self.tapZoneMode = renderConfig.tapZoneMode
        self.tapZoneInversionMode = renderConfig.tapZoneInversionMode
        self.doubleTapZoomMode = renderConfig.doubleTapZoomMode
        applyDoubleTapGestureState()
        self.showPageNumber = renderConfig.showPageNumber

        let currentPageID = viewModel.currentReaderPage?.id
        scrollEngine.currentPageID = currentPageID
        let needsContentRebuild = scrollEngine.needsRebuild(viewModel: viewModel)
        let needsReload =
          needsContentRebuild
          || lastPagesCount != viewModel.pageCount
          || abs(heightCache.lastPageWidth - pageWidth) > 0.1

        if needsReload {
          if isScrollInteractionActive {
            let preCapturedOffset =
              scrollEngine.hasScrolledToInitialPage
              ? captureOffsetWithinPage(currentPageID, in: collectionView) : nil
            scrollEngine.pendingReloadCurrentPageID = currentPageID ?? scrollEngine.currentPageID
            scrollEngine.pendingReloadPreCapturedOffset = preCapturedOffset
          } else {
            handleDataReload(collectionView: collectionView, currentPageID: currentPageID)
          }
        }

        for cell in collectionView.visibleCells {
          if let pageCell = cell as? WebtoonPageCell {
            pageCell.readerBackground = renderConfig.readerBackground
            pageCell.showPageNumber = renderConfig.showPageNumber
          }
        }
        refreshVisibleFooterCells(in: collectionView)

        if !scrollEngine.hasScrolledToInitialPage, scrollEngine.itemCount > 0, currentPageID != nil {
          scrollToInitialPage(currentPageID)
        }

        if let navigationTarget = viewModel.navigationTarget {
          if let targetPageID = navigationPageID(for: navigationTarget),
            itemIndex(forPageID: targetPageID) != nil
          {
            scrollToPage(targetPageID, animated: true)
            self.scrollEngine.currentPageID = targetPageID
            let committedAnchor = ReaderPositionAnchor(
              item: navigationTarget.item,
              focusedPageID: targetPageID
            )
            if viewModel.captureCurrentPositionAnchor() != committedAnchor {
              viewModel.updateCurrentPosition(anchor: committedAnchor)
            }
            clearNavigationTargetIfMatching(navigationTarget)
          } else {
            clearNavigationTargetIfMatching(navigationTarget)
            if self.scrollEngine.currentPageID != currentPageID {
              self.scrollEngine.currentPageID = currentPageID
            }
          }
        } else {
          if self.scrollEngine.currentPageID != currentPageID {
            self.scrollEngine.currentPageID = currentPageID
          }
        }
      }

      private func navigationPageID(for target: ReaderPositionAnchor) -> ReaderPageID? {
        guard let item = target.item else { return nil }
        if let focusedPageID = target.focusedPageID,
          item.pageIDs.contains(focusedPageID) || item.pageID == focusedPageID
        {
          return focusedPageID
        }
        return item.pageID
      }

      private func clearNavigationTargetIfMatching(_ target: ReaderPositionAnchor) {
        viewModel?.clearNavigationTarget(matching: target)
      }

      private func resetContentInsetsIfNeeded(for collectionView: UICollectionView) {
        guard
          collectionView.contentInset != .zero
            || collectionView.verticalScrollIndicatorInsets != .zero
            || collectionView.horizontalScrollIndicatorInsets != .zero
        else {
          return
        }
        collectionView.contentInset = .zero
        collectionView.verticalScrollIndicatorInsets = .zero
        collectionView.horizontalScrollIndicatorInsets = .zero
      }

      private func handleDataReload(
        collectionView: UICollectionView,
        currentPageID: ReaderPageID?,
        preCapturedOffset: CGFloat? = nil
      ) {
        let anchorPageID = currentAnchorPageID(preferredPageID: currentPageID)
        let scrollAnchor =
          captureScrollAnchor(preferredPageID: anchorPageID, in: collectionView)
          ?? preCapturedOffset.flatMap { offsetWithinPage in
            anchorPageID.map {
              ScrollAnchor(pageID: $0, offsetWithinPage: offsetWithinPage)
            }
          }

        // Rebuild content items (updates index mapping to NEW)
        scrollEngine.rebuildContentItemsIfNeeded(viewModel: viewModel)
        pruneStaleMeasurementState()

        let pageCount = self.pageCount
        lastPagesCount = pageCount

        // Reload collection view (layout now matches NEW indices)
        heightCache.rescaleIfNeeded(newWidth: pageWidth)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        // Restore offset using NEW indices + NEW layout (consistent)
        if restoreScrollAnchor(scrollAnchor, in: collectionView) {
          scrollEngine.hasScrolledToInitialPage = true
          return
        }

        scrollEngine.hasScrolledToInitialPage = false
        scrollEngine.resetInitialScrollRetrier()
        if let fallbackPageID = scrollAnchor?.pageID ?? anchorPageID {
          requestInitialScroll(fallbackPageID, delay: WebtoonConstants.layoutReadyDelay)
        }
      }

      private func captureOffsetWithinPage(_ pageID: ReaderPageID?, in collectionView: UICollectionView) -> CGFloat? {
        guard let pageID else { return nil }
        let currentTopY = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        return WebtoonScrollOffset.captureOffsetWithinPage(
          pageID: pageID,
          currentTopY: currentTopY,
          itemIndexForPage: { [weak self] pageID in
            self?.itemIndex(forPageID: pageID)
          },
          frameForItemIndex: { itemIndex in
            collectionView.layoutAttributesForItem(at: IndexPath(item: itemIndex, section: 0))?.frame
          }
        )
      }

      @discardableResult
      private func restoreOffsetWithinPage(
        _ offsetWithinPage: CGFloat,
        for pageID: ReaderPageID,
        in collectionView: UICollectionView
      ) -> Bool {
        guard
          let targetTopY = WebtoonScrollOffset.targetTopYForPage(
            pageID: pageID,
            offsetWithinPage: offsetWithinPage,
            itemIndexForPage: { [weak self] pageID in
              self?.itemIndex(forPageID: pageID)
            },
            frameForItemIndex: { itemIndex in
              collectionView.layoutAttributesForItem(at: IndexPath(item: itemIndex, section: 0))?.frame
            }
          )
        else {
          return false
        }
        let targetOffset = targetTopY - collectionView.adjustedContentInset.top
        let minOffset = -collectionView.adjustedContentInset.top
        let maxOffset = max(
          collectionView.contentSize.height - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom,
          minOffset
        )
        let clampedOffset = WebtoonScrollOffset.clampedY(
          targetOffset,
          min: minOffset,
          max: maxOffset
        )
        collectionView.setContentOffset(
          CGPoint(x: collectionView.contentOffset.x, y: clampedOffset),
          animated: false
        )
        return true
      }

      private func applyPendingReloadIfNeeded() {
        guard let pendingPageID = scrollEngine.pendingReloadCurrentPageID else { return }
        guard let collectionView = collectionView else { return }
        scrollEngine.pendingReloadCurrentPageID = nil
        let preCapturedOffset = scrollEngine.pendingReloadPreCapturedOffset
        scrollEngine.pendingReloadPreCapturedOffset = nil
        let latestCapturedOffset =
          captureOffsetWithinPage(pendingPageID, in: collectionView) ?? preCapturedOffset

        handleDataReload(
          collectionView: collectionView,
          currentPageID: pendingPageID,
          preCapturedOffset: latestCapturedOffset
        )
        updateCurrentPage()
      }

      private func cancelDeferredMaintenance() {
        deferredReloadWorkItem?.cancel()
        deferredReloadWorkItem = nil
        deferredCleanupWorkItem?.cancel()
        deferredCleanupWorkItem = nil
      }

      func teardown() {
        unregisterViewModelObservation()
        scrollController?.clearTarget(self)
        cancelDeferredMaintenance()
        sizeProbeTasks.values.forEach { $0.cancel() }
        sizeProbeTasks.removeAll()
        pendingMeasuredPageIDs.removeAll()
      }

      private func updateViewModelObservation(_ viewModel: ReaderViewModel) {
        guard pagePresentationObserverToken == nil || self.viewModel !== viewModel else { return }
        unregisterViewModelObservation()
        pagePresentationObserverToken = viewModel.addPagePresentationInvalidationObserver {
          [weak self] _ in
          guard let self, let collectionView else { return }
          self.refreshVisibleFooterCells(in: collectionView)
        }
      }

      private func unregisterViewModelObservation() {
        guard let token = pagePresentationObserverToken else { return }
        viewModel?.removePagePresentationInvalidationObserver(token)
        pagePresentationObserverToken = nil
      }

      private func refreshVisibleFooterCells(in collectionView: UICollectionView) {
        for cell in collectionView.visibleCells {
          guard let footerCell = cell as? WebtoonFooterCell,
            let indexPath = collectionView.indexPath(for: footerCell),
            indexPath.item < scrollEngine.contentItems.count,
            case .end(let segmentBookId) = scrollEngine.contentItems[indexPath.item]
          else {
            continue
          }
          footerCell.readerBackground = readerBackground
          footerCell.configure(
            previousBook: viewModel?.endPagePreviousBook(forSegmentBookId: segmentBookId),
            nextBook: viewModel?.nextBook(forSegmentBookId: segmentBookId),
            readListContext: readListContext,
            nextBookOfflineState: viewModel?.nextBookOfflineState(forSegmentBookId: segmentBookId),
            remainingUnreadCount: viewModel?.remainingUnreadCount(forSegmentBookId: segmentBookId),
            onDismiss: onDismiss
          )
        }
      }

      private func scheduleDeferredPendingReloadIfNeeded() {
        guard scrollEngine.pendingReloadCurrentPageID != nil else { return }
        deferredReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
          guard let self else { return }
          self.deferredReloadWorkItem = nil
          guard !self.isScrollInteractionActive else { return }
          self.applyPendingReloadIfNeeded()
        }
        deferredReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(
          deadline: .now() + WebtoonConstants.postScrollReloadDelay,
          execute: workItem
        )
      }

      private func scheduleDeferredCleanupIfNeeded() {
        deferredCleanupWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
          guard let self else { return }
          self.deferredCleanupWorkItem = nil
          guard !self.isScrollInteractionActive else { return }
          self.viewModel?.cleanupDistantImagesAroundCurrentPage()
        }
        deferredCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
          deadline: .now() + WebtoonConstants.postScrollCleanupDelay,
          execute: workItem
        )
      }

      func scrollToPage(_ pageID: ReaderPageID, animated: Bool) {
        guard let collectionView = collectionView else { return }
        guard let itemIndex = itemIndex(forPageID: pageID) else { return }

        if collectionView.contentSize.height > 0 {
          isProgrammaticAnimatedScroll = animated
          collectionView.scrollToItem(
            at: IndexPath(item: itemIndex, section: 0),
            at: .top,
            animated: animated
          )
        } else {
          requestScrollToPage(
            pageID, animated: animated, delay: WebtoonConstants.layoutReadyDelay)
        }
      }

      func requestScrollToPage(_ pageID: ReaderPageID, animated: Bool, delay: TimeInterval) {
        scheduleOnMain(after: delay) { [weak self] in
          guard let self = self,
            let collectionView = self.collectionView
          else { return }
          guard let itemIndex = self.scrollEngine.itemIndex(forPageID: pageID) else { return }
          self.isProgrammaticAnimatedScroll = animated
          collectionView.scrollToItem(
            at: IndexPath(item: itemIndex, section: 0),
            at: .top,
            animated: animated
          )
        }
      }

      func scrollToInitialPage(_ pageID: ReaderPageID?) {
        guard !scrollEngine.hasScrolledToInitialPage else { return }
        guard let collectionView = collectionView,
          let itemIndex = itemIndex(forPageID: pageID),
          collectionView.bounds.width > 0 && collectionView.bounds.height > 0
        else {
          if !scrollEngine.hasScrolledToInitialPage {
            requestInitialScroll(pageID, delay: WebtoonConstants.initialScrollRetryDelay)
          }
          return
        }

        collectionView.layoutIfNeeded()

        guard collectionView.contentSize.height > 0 else {
          if !scrollEngine.hasScrolledToInitialPage {
            requestInitialScroll(pageID, delay: WebtoonConstants.initialScrollRetryDelay)
          }
          return
        }

        let indexPath = IndexPath(item: itemIndex, section: 0)
        scrollEngine.hasScrolledToInitialPage = true
        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        collectionView.layoutIfNeeded()
      }

      // MARK: - UICollectionViewDataSource

      func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
        -> Int
      {
        scrollEngine.itemCount
      }

      func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
      {
        guard indexPath.item < scrollEngine.contentItems.count else {
          return UICollectionViewCell()
        }

        switch scrollEngine.contentItems[indexPath.item] {
        case .end(let segmentBookId):
          let item = collectionView.dequeueReusableCell(
            withReuseIdentifier: "WebtoonFooterCell",
            for: indexPath
          )
          guard let cell = item as? WebtoonFooterCell else {
            assertionFailure("Failed to dequeue WebtoonFooterCell")
            return item
          }
          cell.readerBackground = readerBackground
          cell.configure(
            previousBook: viewModel?.endPagePreviousBook(forSegmentBookId: segmentBookId),
            nextBook: viewModel?.nextBook(forSegmentBookId: segmentBookId),
            readListContext: readListContext,
            nextBookOfflineState: viewModel?.nextBookOfflineState(forSegmentBookId: segmentBookId),
            remainingUnreadCount: viewModel?.remainingUnreadCount(forSegmentBookId: segmentBookId),
            onDismiss: onDismiss
          )
          return cell
        case .page(let pageID):
          let page = viewModel?.page(for: pageID)
          ensureMeasuredHeightProbe(for: pageID, page: page)

          let item = collectionView.dequeueReusableCell(
            withReuseIdentifier: "WebtoonPageCell",
            for: indexPath
          )
          guard let cell = item as? WebtoonPageCell else {
            assertionFailure("Failed to dequeue WebtoonPageCell")
            return item
          }
          cell.readerBackground = readerBackground
          cell.onRetry = { [weak self] in
            Task { @MainActor [weak self] in
              await self?.loadImage(for: pageID)
            }
          }

          let displayImage = displayImageIfReady(
            viewModel?.preloadedImage(for: pageID),
            for: pageID,
            page: page
          )
          let pageLabel =
            viewModel?.displayPageNumber(for: pageID).map(String.init)
            ?? String(pageID.pageNumber)

          if displayImage == nil, hasKnownHeight(for: pageID, page: page) {
            Task { @MainActor [weak self] in
              guard let self = self else { return }
              await self.loadImage(for: pageID)
            }
          }

          cell.configure(
            pageLabel: pageLabel,
            image: displayImage,
            showPageNumber: showPageNumber
          )

          return cell
        }
      }

      // MARK: - UICollectionViewDelegateFlowLayout

      func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
      ) -> CGSize {
        guard indexPath.item < scrollEngine.contentItems.count else {
          return CGSize(width: pageWidth, height: 0)
        }

        switch scrollEngine.contentItems[indexPath.item] {
        case .end:
          return CGSize(width: pageWidth, height: WebtoonConstants.footerHeight)
        case .page(let pageID):
          guard let page = viewModel?.page(for: pageID) else {
            return CGSize(width: pageWidth, height: WebtoonConstants.measuringPlaceholderHeight)
          }
          if let preloadedImage = viewModel?.preloadedImage(for: pageID),
            let pixelSize = webtoonPixelSize(from: preloadedImage)
          {
            _ = heightCache.updateHeight(for: pageID, pixelSize: pixelSize, pageWidth: pageWidth)
          }
          if !hasKnownHeight(for: pageID, page: page) {
            return CGSize(width: pageWidth, height: WebtoonConstants.measuringPlaceholderHeight)
          }
          let height = heightCache.height(for: pageID, page: page, pageWidth: pageWidth)
          let scale = collectionView.traitCollection.displayScale
          let alignedHeight = scale > 0 ? ceil(height * scale) / scale : height
          return CGSize(width: pageWidth, height: alignedHeight)
        }
      }

      // MARK: - UICollectionViewDelegate

      func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelDeferredMaintenance()
        isUserScrolling = true
        isProgrammaticAnimatedScroll = false
      }

      func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isUserScrolling {
          updateCurrentPage(commitToViewModel: false)
        }
      }

      func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finalizeScrollInteraction()
      }

      func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
          finalizeScrollInteraction()
        }
      }

      func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticAnimatedScroll = false
        finalizeScrollInteraction()
      }

      private func finalizeScrollInteraction() {
        isUserScrolling = false
        applyPendingMeasuredLayoutUpdatesIfNeeded()
        updateCurrentPage()
        scheduleDeferredPendingReloadIfNeeded()
        scheduleDeferredCleanupIfNeeded()
      }

      private func updateCurrentPage(commitToViewModel: Bool = true) {
        guard let collectionView = collectionView else { return }
        let totalItems = scrollEngine.itemCount
        guard totalItems > 0 else { return }

        let scrollOffset = collectionView.contentOffset.y
        let scrollViewHeight = collectionView.bounds.height
        let viewportBottom = scrollOffset + scrollViewHeight
        let visibleItemIndices = collectionView.indexPathsForVisibleItems.map(\.item)

        let newCurrentItemIndex = WebtoonContentItems.lastVisibleItemIndex(
          itemCount: totalItems,
          viewportBottom: viewportBottom,
          threshold: WebtoonConstants.bottomThreshold,
          visibleItemIndices: visibleItemIndices
        ) { itemIndex in
          collectionView.layoutAttributesForItem(at: IndexPath(item: itemIndex, section: 0))?.frame
        }

        guard
          let resolvedPageID = scrollEngine.resolvedPageID(
            forItemIndex: newCurrentItemIndex,
            viewModel: viewModel
          )
        else {
          return
        }

        if scrollEngine.currentPageID != resolvedPageID {
          commitLastPageBeforeBookBoundaryIfNeeded(nextPageID: resolvedPageID)
          scrollEngine.currentPageID = resolvedPageID
        }
        if commitToViewModel, viewModel?.currentReaderPage?.id != resolvedPageID {
          viewModel?.updateCurrentPosition(pageID: resolvedPageID)
        }
      }

      private func commitLastPageBeforeBookBoundaryIfNeeded(nextPageID: ReaderPageID) {
        let currentBookId = scrollEngine.currentPageID?.bookId ?? viewModel?.currentReaderPage?.bookId
        guard let currentBookId,
          currentBookId != nextPageID.bookId,
          let lastPageID = viewModel?.lastPageID(forSegmentBookId: currentBookId),
          viewModel?.currentReaderPage?.id != lastPageID
        else { return }

        viewModel?.updateCurrentPosition(pageID: lastPageID)
      }

      // MARK: - Image Loading

      @MainActor
      func loadImage(for pageID: ReaderPageID) async {
        guard let viewModel = viewModel else {
          return
        }

        if let preloadedImage = viewModel.preloadedImage(for: pageID) {
          if let pixelSize = webtoonPixelSize(from: preloadedImage) {
            applyMeasuredHeightIfNeeded(for: pageID, pixelSize: pixelSize)
          }
          if let page = viewModel.page(for: pageID),
            hasKnownHeight(for: pageID, page: page)
          {
            pageCell(for: pageID)?.setImage(preloadedImage)
          }
          return
        }

        if let image = await viewModel.preloadImage(for: pageID) {
          if let pixelSize = webtoonPixelSize(from: image) {
            applyMeasuredHeightIfNeeded(for: pageID, pixelSize: pixelSize)
          }
          if let page = viewModel.page(for: pageID),
            hasKnownHeight(for: pageID, page: page)
          {
            pageCell(for: pageID)?.setImage(image)
          }
        } else {
          showImageError(for: pageID)
        }
      }

      private func pageCell(for pageID: ReaderPageID) -> WebtoonPageCell? {
        guard let collectionView else { return nil }
        guard let indexPath = indexPath(forPageID: pageID) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? WebtoonPageCell
      }

      private func showImageError(for pageID: ReaderPageID) {
        pageCell(for: pageID)?.showError(failure: viewModel?.imageLoadFailure(for: pageID))
      }

      // MARK: - Tap Gesture Handling

      @objc func handleLongPress(_: UILongPressGestureRecognizer) {}

      @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let collectionView = collectionView else { return }
        if collectionView.isDragging || collectionView.isDecelerating { return }
        if doubleTapZoomMode == .disabled { return }

        let location = gesture.location(in: collectionView)
        requestZoom(at: location)
      }

      @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard !hasTriggeredZoomGesture else { return }
        guard let collectionView else { return }
        guard viewModel?.isZoomed != true else { return }
        guard !isScrollInteractionActive else { return }

        let location = gesture.location(in: collectionView)
        dispatchTapZoneTap(at: location, in: collectionView)
      }

      @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let collectionView = collectionView else { return }

        switch gesture.state {
        case .began:
          hasTriggeredZoomGesture = false
        case .changed:
          if hasTriggeredZoomGesture { return }
          let delta = gesture.scale - 1.0
          guard delta > 0.05 else { return }
          hasTriggeredZoomGesture = true
          let location = gesture.location(in: collectionView)
          requestZoom(at: location)
        case .ended, .cancelled, .failed:
          hasTriggeredZoomGesture = false
        default:
          break
        }
      }

      // MARK: - UIGestureRecognizerDelegate

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
      {
        touch.view?.hasInteractiveAncestor != true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        // Always allow simultaneous recognition to ensure scrolling and context menus work.
        return true
      }

      private func requestZoom(at location: CGPoint) {
        guard let result = pageIndexAndAnchor(for: location) else { return }
        onZoomRequest?(result.pageID, result.anchor)
      }

      private func dispatchTapZoneTap(at location: CGPoint, in collectionView: UICollectionView) {
        guard viewModel?.isZoomed != true else { return }
        guard !isScrollInteractionActive else { return }

        let visibleBounds = collectionView.bounds
        guard visibleBounds.width > 0, visibleBounds.height > 0 else { return }

        let normalizedX = min(max((location.x - visibleBounds.minX) / visibleBounds.width, 0), 1)
        let normalizedY = min(max((location.y - visibleBounds.minY) / visibleBounds.height, 0), 1)
        onTapZoneTap?(normalizedX, normalizedY)
      }

      func applyDoubleTapGestureState() {
        doubleTapGesture?.isEnabled = doubleTapZoomMode.isEnabled
      }

      private func pageIndexAndAnchor(for location: CGPoint) -> (pageID: ReaderPageID, anchor: CGPoint)? {
        guard let collectionView = collectionView else { return nil }

        if let indexPath = collectionView.indexPathForItem(at: location),
          let pageID = scrollEngine.resolvedPageID(
            forItemIndex: indexPath.item,
            viewModel: viewModel
          )
        {
          if let cell = collectionView.cellForItem(at: indexPath) {
            let local = cell.contentView.convert(location, from: collectionView)
            return (pageID, normalizedAnchor(in: cell.contentView.bounds, location: local))
          }
          if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
            return (pageID, normalizedAnchor(in: attributes.frame, location: location))
          }
        }

        guard let fallbackPageID = scrollEngine.currentPageID else { return nil }
        guard let fallbackIndexPath = indexPath(forPageID: fallbackPageID) else { return nil }
        if let cell = collectionView.cellForItem(at: fallbackIndexPath) {
          let local = cell.contentView.convert(location, from: collectionView)
          return (fallbackPageID, normalizedAnchor(in: cell.contentView.bounds, location: local))
        }
        if let attributes = collectionView.layoutAttributesForItem(at: fallbackIndexPath) {
          return (fallbackPageID, normalizedAnchor(in: attributes.frame, location: location))
        }
        return nil
      }

      private func normalizedAnchor(in frame: CGRect, location: CGPoint) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let localX = location.x - frame.minX
        let localY = location.y - frame.minY
        let x = min(max(localX / frame.width, 0), 1)
        let y = min(max(localY / frame.height, 0), 1)
        return CGPoint(x: x, y: y)
      }

      private func scrollUp(collectionView: UICollectionView, screenHeight: CGFloat) {
        let currentOffset = collectionView.contentOffset.y
        let scrollAmount = screenHeight * CGFloat(AppConfig.webtoonTapScrollPercentage / 100.0)
        let targetOffset = max(currentOffset - scrollAmount, 0)
        scrollToOffsetIfNeeded(targetOffset, in: collectionView)
      }

      private func scrollDown(collectionView: UICollectionView, screenHeight: CGFloat) {
        let currentOffset = collectionView.contentOffset.y
        let scrollAmount = screenHeight * CGFloat(AppConfig.webtoonTapScrollPercentage / 100.0)
        let maxOffset = max(collectionView.contentSize.height - screenHeight, 0)
        let targetOffset = min(
          currentOffset + scrollAmount,
          maxOffset
        )
        scrollToOffsetIfNeeded(targetOffset, in: collectionView)
      }

      func scroll(_ direction: WebtoonScrollDirection) {
        guard let collectionView else { return }

        let screenHeight = collectionView.bounds.height
        guard screenHeight > 0 else { return }

        switch direction {
        case .up:
          scrollUp(collectionView: collectionView, screenHeight: screenHeight)
        case .down:
          scrollDown(collectionView: collectionView, screenHeight: screenHeight)
        }
      }

      private func scrollToOffsetIfNeeded(_ targetOffset: CGFloat, in collectionView: UICollectionView) {
        let currentOffset = collectionView.contentOffset.y
        guard abs(targetOffset - currentOffset) > WebtoonConstants.offsetEpsilon else {
          isProgrammaticAnimatedScroll = false
          return
        }
        cancelDeferredMaintenance()
        preheatPages(at: targetOffset, in: collectionView)
        let shouldAnimate = AppConfig.animateTapTurns
        isProgrammaticAnimatedScroll = shouldAnimate
        collectionView.setContentOffset(
          CGPoint(x: 0, y: targetOffset),
          animated: shouldAnimate
        )
        if !shouldAnimate {
          finalizeScrollInteraction()
        }
      }

      private func preheatPages(at targetOffset: CGFloat, in collectionView: UICollectionView) {
        let centerY = targetOffset + collectionView.bounds.height / 2
        let centerPoint = CGPoint(x: collectionView.bounds.width / 2, y: centerY)
        guard let indexPath = collectionView.indexPathForItem(at: centerPoint),
          let targetPageID = scrollEngine.resolvedPageID(
            forItemIndex: indexPath.item,
            viewModel: viewModel
          ),
          let pageIDs = viewModel?.neighboringPageIDs(
            around: targetPageID,
            radius: WebtoonConstants.preheatRadius
          ),
          !pageIDs.isEmpty
        else { return }
        Task(priority: .utility) { @MainActor [weak self] in
          guard let viewModel = self?.viewModel else { return }
          for pageID in pageIDs {
            _ = await viewModel.preloadImage(for: pageID)
          }
        }
      }
    }
  }
#endif
