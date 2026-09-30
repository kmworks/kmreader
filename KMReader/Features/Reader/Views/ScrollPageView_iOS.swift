#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  struct ScrollPageView: UIViewRepresentable {
    let mode: PageViewMode
    let viewportSize: CGSize
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let navigationAnimationDuration: TimeInterval
    let renderConfig: ReaderRenderConfig
    @Bindable var viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    init(
      mode: PageViewMode,
      viewportSize: CGSize,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      navigationAnimationDuration: TimeInterval = 0.3,
      renderConfig: ReaderRenderConfig,
      viewModel: ReaderViewModel,
      readListContext: ReaderReadListContext?,
      onDismiss: @escaping () -> Void,
      onTapZoneTap: @escaping ReaderTapZoneTapHandler
    ) {
      self.mode = mode
      self.viewportSize = viewportSize
      self.readingDirection = readingDirection
      self.splitWidePageMode = splitWidePageMode
      self.navigationAnimationDuration = navigationAnimationDuration
      self.renderConfig = renderConfig
      self.viewModel = viewModel
      self.readListContext = readListContext
      self.onDismiss = onDismiss
      self.onTapZoneTap = onTapZoneTap
    }

    private var shouldDisableScrollInteraction: Bool {
      #if os(tvOS)
        true
      #else
        viewModel.isZoomed
      #endif
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
      let layout = UICollectionViewFlowLayout()
      layout.scrollDirection = mode.isVertical ? .vertical : .horizontal
      layout.minimumLineSpacing = 0
      layout.minimumInteritemSpacing = 0

      let collectionView = NativePagedLayoutAwareCollectionView(
        frame: .zero,
        collectionViewLayout: layout
      )
      collectionView.delegate = context.coordinator
      collectionView.dataSource = context.coordinator
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      collectionView.showsHorizontalScrollIndicator = false
      collectionView.showsVerticalScrollIndicator = false
      collectionView.contentInsetAdjustmentBehavior = .never
      collectionView.bounces = false
      collectionView.isPrefetchingEnabled = false
      collectionView.semanticContentAttribute = .forceLeftToRight

      #if os(iOS) || os(macOS)
        collectionView.isPagingEnabled = true
        collectionView.scrollsToTop = false
      #endif

      collectionView.register(
        NativePagedPageCell.self,
        forCellWithReuseIdentifier: Coordinator.pageCellReuseIdentifier
      )
      collectionView.register(
        NativePagedEndCell.self,
        forCellWithReuseIdentifier: Coordinator.endCellReuseIdentifier
      )

      let singleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleSingleTap(_:))
      )
      singleTapGesture.numberOfTapsRequired = 1
      singleTapGesture.cancelsTouchesInView = false
      singleTapGesture.delegate = context.coordinator
      collectionView.addGestureRecognizer(singleTapGesture)

      let doubleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDoubleTap(_:))
      )
      doubleTapGesture.numberOfTapsRequired = 2
      doubleTapGesture.cancelsTouchesInView = false
      doubleTapGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: doubleTapGesture)
      collectionView.addGestureRecognizer(doubleTapGesture)
      context.coordinator.doubleTapGesture = doubleTapGesture

      let longPressGesture = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressGesture.cancelsTouchesInView = false
      longPressGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: longPressGesture)
      collectionView.addGestureRecognizer(longPressGesture)

      context.coordinator.collectionView = collectionView
      context.coordinator.applyDoubleTapGestureState()
      collectionView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleCollectionViewLayout()
      }
      collectionView.shouldBeginPan = { [weak coordinator = context.coordinator] pan in
        coordinator?.shouldBeginPaging(with: pan) ?? true
      }
      return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
      context.coordinator.update(parent: self, collectionView: collectionView)
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      collectionView.semanticContentAttribute = .forceLeftToRight
      collectionView.isScrollEnabled = !shouldDisableScrollInteraction
      if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
        let targetDirection: UICollectionView.ScrollDirection = mode.isVertical ? .vertical : .horizontal
        if layout.scrollDirection != targetDirection {
          layout.scrollDirection = targetDirection
          layout.invalidateLayout()
        }
      }
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
      coordinator.synchronizeCurrentPositionBeforeTeardown(in: uiView)
      coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
      UIScrollViewDelegate, UIGestureRecognizerDelegate, NativePagedPagePresentationHost
    {
      private struct RenderInputs: Equatable {
        let readingDirection: ReadingDirection
        let splitWidePageMode: SplitWidePageMode
        let renderConfig: ReaderRenderConfig
        let readListContext: ReaderReadListContext?
      }

      static let pageCellReuseIdentifier = "NativePagedPageCell"
      static let endCellReuseIdentifier = "NativePagedEndCell"

      var parent: ScrollPageView
      weak var collectionView: UICollectionView?

      private let engine = ScrollReaderEngine()
      private let pagePresentationCoordinator = NativePagedPagePresentationCoordinator()
      private var lastViewportSize: CGSize = .zero
      private var lastRenderInputs: RenderInputs?
      private var needsViewportResyncAfterInteraction = false
      private var pendingProgrammaticTargetOffset: CGPoint?
      private var pendingUserInteractionTargetItem: ReaderViewItem?
      private var pendingNavigationTarget: ReaderPositionAnchor?
      private var deferredViewModelCommitTask: Task<Void, Never>?
      private var visiblePreloadTask: Task<Void, Never>?
      private var visiblePreloadItem: ReaderViewItem?
      private var applicationWillResignActiveObserver: NSObjectProtocol?
      weak var doubleTapGesture: UITapGestureRecognizer?

      init(_ parent: ScrollPageView) {
        self.parent = parent
        super.init()
        pagePresentationCoordinator.host = self
      }

      func teardown() {
        deferredViewModelCommitTask?.cancel()
        deferredViewModelCommitTask = nil
        visiblePreloadTask?.cancel()
        visiblePreloadTask = nil
        visiblePreloadItem = nil
        needsViewportResyncAfterInteraction = false
        pendingProgrammaticTargetOffset = nil
        pendingUserInteractionTargetItem = nil
        pendingNavigationTarget = nil
        if let applicationWillResignActiveObserver {
          NotificationCenter.default.removeObserver(applicationWillResignActiveObserver)
          self.applicationWillResignActiveObserver = nil
        }
        pagePresentationCoordinator.teardown()
        engine.teardown()
      }

      func synchronizeCurrentPositionBeforeTeardown(in collectionView: UICollectionView) {
        deferredViewModelCommitTask?.cancel()
        deferredViewModelCommitTask = nil
        collectionView.layoutIfNeeded()

        guard let item = currentAnchorItem(in: collectionView) else { return }
        synchronizeViewModelCurrentPosition(to: item)
      }

      func update(parent: ScrollPageView, collectionView: UICollectionView) {
        self.parent = parent
        self.collectionView = collectionView
        applyDoubleTapGestureState()
        installApplicationObserverIfNeeded()
        pagePresentationCoordinator.update(viewModel: parent.viewModel)

        let displayedItems = parent.mode.displayOrderedItems(parent.viewModel.viewItems)
        let anchorItem = currentAnchorItem(in: collectionView)
        let sizeChanged = updateLayoutIfNeeded(for: collectionView)
        let renderInputsChanged = updateRenderInputsIfNeeded()
        var refreshedVisibleContent = false

        if engine.installInitialItemsIfNeeded(displayedItems) {
          collectionView.reloadData()
          collectionView.layoutIfNeeded()
          refreshedVisibleContent = synchronizeInitialPositionIfPossible(in: collectionView)
        } else if displayedItems != engine.renderedItems {
          if isScrollInteractionActive(in: collectionView) || engine.isProgrammaticScrolling {
            engine.queueRenderedItems(displayedItems, anchor: anchorItem)
          } else {
            // A rebuild restores from the committed position: the view model's
            // resolution is split-side aware, the engine's stale items are not.
            applyRenderedItems(
              displayedItems,
              anchor: parent.viewModel.currentViewItem() ?? anchorItem,
              commitAfterRestore: parent.viewModel.navigationTarget == nil,
              in: collectionView
            )
          }
          refreshedVisibleContent = true
        }

        if engine.hasSyncedInitialPosition, sizeChanged, !refreshedVisibleContent {
          if isScrollInteractionActive(in: collectionView) {
            needsViewportResyncAfterInteraction = true
            refreshVisibleCells(in: collectionView)
            refreshedVisibleContent = true
          } else if let anchorItem {
            restoreViewportAnchor(anchorItem, in: collectionView)
            refreshedVisibleContent = true
          }
        }

        if let navigationTarget = parent.viewModel.navigationTarget {
          handleNavigationChange(navigationTarget, in: collectionView)
        } else if renderInputsChanged && !refreshedVisibleContent {
          refreshVisibleCells(in: collectionView)
        }

        pagePresentationCoordinator.flushIfPossible()
      }

      func applyDoubleTapGestureState() {
        doubleTapGesture?.isEnabled = parent.renderConfig.doubleTapZoomMode.isEnabled
      }

      private func updateRenderInputsIfNeeded() -> Bool {
        let renderInputs = RenderInputs(
          readingDirection: parent.readingDirection,
          splitWidePageMode: parent.splitWidePageMode,
          renderConfig: parent.renderConfig,
          readListContext: parent.readListContext
        )
        let changed = lastRenderInputs != renderInputs
        lastRenderInputs = renderInputs
        return changed
      }

      private func installApplicationObserverIfNeeded() {
        guard applicationWillResignActiveObserver == nil else { return }
        applicationWillResignActiveObserver = NotificationCenter.default.addObserver(
          forName: UIApplication.willResignActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.handleApplicationWillResignActive()
          }
        }
      }

      private func updateLayoutIfNeeded(for collectionView: UICollectionView) -> Bool {
        let viewportSize = resolvedViewportSize(for: collectionView)
        guard viewportSize.width > 0, viewportSize.height > 0 else { return false }

        let sizeChanged = viewportSize != lastViewportSize
        lastViewportSize = viewportSize

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
          layout.itemSize != viewportSize
        {
          layout.itemSize = viewportSize
          layout.invalidateLayout()
        }

        return sizeChanged
      }

      private func resolvedViewportSize(for collectionView: UICollectionView) -> CGSize {
        let boundsSize = collectionView.bounds.size
        // The reader content ignores safe area, so the visible collection view bounds
        // are the only reliable paging viewport after layout.
        if boundsSize.width > 0, boundsSize.height > 0 {
          return boundsSize
        }
        return parent.viewportSize
      }

      private func canApplyInitialPosition(in collectionView: UICollectionView) -> Bool {
        let boundsSize = collectionView.bounds.size
        return collectionView.window != nil && boundsSize.width > 0 && boundsSize.height > 0
      }

      @discardableResult
      private func synchronizeInitialPositionIfPossible(in collectionView: UICollectionView) -> Bool {
        guard
          let currentItem = engine.prepareInitialPosition(
            anchor: parent.viewModel.captureCurrentPositionAnchor()
          )
        else {
          return false
        }
        guard canApplyInitialPosition(in: collectionView) else { return false }

        guard scrollToItem(currentItem, animated: false, in: collectionView) else {
          return false
        }
        guard let committedItem = engine.completeInitialPosition() else { return false }
        preloadVisiblePages(for: committedItem)
        refreshVisibleCells(in: collectionView)
        if parent.viewModel.navigationTarget == nil {
          scheduleViewModelCommit(for: committedItem)
        }
        Task { @MainActor [weak self] in
          guard let self, self.engine.committedItem == committedItem else { return }
          await self.parent.viewModel.preloadPages(bypassThrottle: true)
        }
        return true
      }

      func handleCollectionViewLayout() {
        guard let collectionView else { return }
        if synchronizeInitialPositionIfPossible(in: collectionView) {
          pagePresentationCoordinator.flushIfPossible()
        }
      }

      private func applyRenderedItems(
        _ items: [ReaderViewItem],
        anchor: ReaderViewItem?,
        commitAfterRestore: Bool,
        in collectionView: UICollectionView
      ) {
        engine.replaceRenderedItems(items)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        if let anchor = engine.resolveItem(anchor) {
          _ = scrollToItem(anchor, animated: false, in: collectionView)
        }

        refreshVisibleCells(in: collectionView)
        if commitAfterRestore {
          commitRestoredItemIfNeeded(anchor: anchor, in: collectionView)
        }
      }

      @discardableResult
      private func applyQueuedRenderedItemsIfNeeded(
        in collectionView: UICollectionView,
        anchorFallback: ReaderViewItem? = nil,
        preferAnchorFallback: Bool = false
      ) -> Bool {
        guard
          let update = engine.consumeQueuedRenderedItems(
            anchorFallback: anchorFallback ?? currentAnchorItem(in: collectionView),
            preferAnchorFallback: preferAnchorFallback
          )
        else {
          return false
        }

        applyRenderedItems(
          update.items,
          anchor: update.anchor,
          commitAfterRestore: parent.viewModel.navigationTarget == nil,
          in: collectionView
        )
        return true
      }

      private func handleNavigationChange(
        _ navigationTarget: ReaderPositionAnchor,
        in collectionView: UICollectionView
      ) {
        // While the user is in the middle of a swipe (drag or its deceleration), ignore
        // tap-initiated navigation. The drag's intent dominates; layering a programmatic
        // scroll over natural deceleration produces a double page advance.
        if isScrollInteractionActive(in: collectionView) {
          clearNavigationTargetIfCurrent(navigationTarget)
          return
        }

        guard
          let resolvedTarget = strictNavigationAnchor(for: navigationTarget),
          let targetItem = resolvedTarget.item
        else {
          clearNavigationTargetIfCurrent(navigationTarget)
          return
        }
        pendingNavigationTarget = navigationTarget

        guard engine.hasSyncedInitialPosition else {
          engine.setPendingInitialAnchor(resolvedTarget)
          return
        }

        if engine.isProgrammaticScrolling && engine.isPendingProgrammaticCommit(targetItem) {
          refreshVisibleCells(in: collectionView)
          return
        }

        if centeredItem(in: collectionView) == targetItem {
          engine.clearPendingProgrammaticCommit()
          commitItemIfNeeded(targetItem, in: collectionView)
          return
        }

        _ = scrollToItem(targetItem, animated: true, in: collectionView)
      }

      private func strictNavigationAnchor(
        for target: ReaderPositionAnchor
      ) -> ReaderPositionAnchor? {
        let resolvedItem: ReaderViewItem?
        if let targetItem = target.item,
          let exactItem = engine.renderedItems.first(where: { $0 == targetItem })
        {
          resolvedItem = exactItem
        } else if let focusedPageID = target.focusedPageID {
          resolvedItem = engine.renderedItems.first(where: { $0.pageIDs.contains(focusedPageID) })
        } else {
          resolvedItem = nil
        }

        guard let resolvedItem else { return nil }
        let focusedPageID =
          target.focusedPageID.flatMap { resolvedItem.pageIDs.contains($0) ? $0 : nil }
          ?? resolvedItem.pageID
        return ReaderPositionAnchor(
          item: resolvedItem,
          focusedPageID: focusedPageID,
          preferredSplitPart: resolvedItem.preferredSplitPart(preserving: target)
        )
      }

      private func clearNavigationTargetIfCurrent(_ target: ReaderPositionAnchor) {
        parent.viewModel.clearNavigationTarget(matching: target)
        if pendingNavigationTarget == target {
          pendingNavigationTarget = nil
        }
      }

      @discardableResult
      private func scrollToItem(
        _ item: ReaderViewItem,
        animated: Bool,
        in collectionView: UICollectionView
      ) -> Bool {
        guard let index = engine.renderedItems.firstIndex(of: item) else {
          return false
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutIfNeeded()
        guard let targetOffset = targetContentOffset(for: indexPath, in: collectionView) else {
          return false
        }

        if isEquivalentContentOffset(targetOffset, to: collectionView.contentOffset) {
          guard isPositionedOnItem(item, in: collectionView) else {
            return false
          }
          pendingProgrammaticTargetOffset = nil
          engine.clearPendingProgrammaticCommit()
          refreshVisibleCells(in: collectionView)
          if animated {
            commitItemIfNeeded(item, in: collectionView)
          }
          return true
        }

        let shouldAnimate = animated && parent.navigationAnimationDuration > 0

        if shouldAnimate {
          engine.beginProgrammaticScroll(to: item)
          pendingProgrammaticTargetOffset = targetOffset
          preloadVisiblePages(for: item)
          collectionView.setContentOffset(targetOffset, animated: true)
        } else {
          pendingProgrammaticTargetOffset = nil
          engine.clearPendingProgrammaticCommit()
          collectionView.setContentOffset(targetOffset, animated: false)
          collectionView.layoutIfNeeded()
          guard isPositionedOnItem(item, in: collectionView) else {
            return false
          }
          refreshVisibleCells(in: collectionView)
          if animated {
            commitItemIfNeeded(item, in: collectionView)
          }
        }
        return true
      }

      private func targetContentOffset(
        for indexPath: IndexPath,
        in collectionView: UICollectionView
      ) -> CGPoint? {
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
          return nil
        }

        let proposedOffset = CGPoint(
          x: parent.mode.isVertical ? collectionView.contentOffset.x : attributes.frame.minX,
          y: parent.mode.isVertical ? attributes.frame.minY : collectionView.contentOffset.y
        )
        return clampedContentOffset(proposedOffset, in: collectionView)
      }

      private func clampedContentOffset(
        _ proposedOffset: CGPoint,
        in collectionView: UICollectionView
      ) -> CGPoint {
        let inset = collectionView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(
          minX,
          collectionView.contentSize.width - collectionView.bounds.width + inset.right
        )
        let maxY = max(
          minY,
          collectionView.contentSize.height - collectionView.bounds.height + inset.bottom
        )

        return CGPoint(
          x: min(max(proposedOffset.x, minX), maxX),
          y: min(max(proposedOffset.y, minY), maxY)
        )
      }

      private func isEquivalentContentOffset(_ lhs: CGPoint, to rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
      }

      private func currentAnchorItem(in collectionView: UICollectionView) -> ReaderViewItem? {
        if let programmaticTargetItem = engine.programmaticTargetItem {
          return programmaticTargetItem
        }
        if let pendingUserInteractionTargetItem {
          return engine.resolveItem(pendingUserInteractionTargetItem) ?? pendingUserInteractionTargetItem
        }
        return centeredItem(in: collectionView)
          ?? parent.viewModel.currentViewItem()
          ?? engine.committedItem
      }

      private func isPositionedOnItem(_ item: ReaderViewItem, in collectionView: UICollectionView) -> Bool {
        centeredItem(in: collectionView) == item
      }

      private func synchronizeViewModelCurrentPosition(to item: ReaderViewItem) {
        let resolvedItem = engine.resolveItem(item) ?? item
        engine.commit(resolvedItem)
        let commit = positionCommit(for: resolvedItem)
        commitViewModelPosition(
          commit.anchor,
          matchingNavigationTarget: commit.navigationTarget
        )
      }

      private func clearProgrammaticScrollState() {
        pendingProgrammaticTargetOffset = nil
        engine.cancelProgrammaticScroll()
      }

      private func cancelProgrammaticNavigationIfNeeded() {
        guard engine.isProgrammaticScrolling || engine.hasPendingProgrammaticCommit else { return }
        let navigationTarget = pendingNavigationTarget
        clearProgrammaticScrollState()
        if let navigationTarget {
          clearNavigationTargetIfCurrent(navigationTarget)
        }
      }

      private func resolvedSwipeTargetItem(
        for targetContentOffset: CGPoint,
        in collectionView: UICollectionView
      ) -> ReaderViewItem? {
        let bounds = collectionView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let inset = collectionView.adjustedContentInset
        let pageExtent = parent.mode.isVertical ? bounds.height : bounds.width
        guard pageExtent > 0 else { return nil }

        let rawIndex: CGFloat
        if parent.mode.isVertical {
          rawIndex = (targetContentOffset.y + inset.top) / pageExtent
        } else {
          rawIndex = (targetContentOffset.x + inset.left) / pageExtent
        }

        let index = min(
          max(Int(rawIndex.rounded()), 0),
          max(engine.renderedItems.count - 1, 0)
        )
        return renderedItem(at: index)
      }

      private func centeredItem(in collectionView: UICollectionView) -> ReaderViewItem? {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return engine.committedItem }

        let center = CGPoint(
          x: collectionView.bounds.midX,
          y: collectionView.bounds.midY
        )

        let nearestIndexPath = visibleIndexPaths.min { lhs, rhs in
          let lhsDistance = distanceFromCenter(of: lhs, to: center, in: collectionView)
          let rhsDistance = distanceFromCenter(of: rhs, to: center, in: collectionView)
          return lhsDistance < rhsDistance
        }

        guard let nearestIndexPath, let item = renderedItem(at: nearestIndexPath.item) else {
          return engine.committedItem
        }
        return item
      }

      private func distanceFromCenter(
        of indexPath: IndexPath,
        to center: CGPoint,
        in collectionView: UICollectionView
      ) -> CGFloat {
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
          return .greatestFiniteMagnitude
        }
        let dx = attributes.center.x - center.x
        let dy = attributes.center.y - center.y
        return sqrt(dx * dx + dy * dy)
      }

      private func commitCenteredItem(in collectionView: UICollectionView) {
        guard let item = centeredItem(in: collectionView) else { return }
        commitItemIfNeeded(item, in: collectionView)
      }

      private func commitRestoredItemIfNeeded(
        anchor: ReaderViewItem?,
        in collectionView: UICollectionView
      ) {
        if let item = engine.resolveItem(anchor) {
          commitItemIfNeeded(item, in: collectionView)
          return
        }
        commitCenteredItem(in: collectionView)
      }

      private func restoreViewportAnchor(
        _ anchor: ReaderViewItem,
        in collectionView: UICollectionView
      ) {
        _ = scrollToItem(anchor, animated: false, in: collectionView)
        refreshVisibleCells(in: collectionView)
        if parent.viewModel.navigationTarget == nil {
          commitRestoredItemIfNeeded(anchor: anchor, in: collectionView)
        }
      }

      @discardableResult
      private func finalizeDeferredViewportResyncIfNeeded(in collectionView: UICollectionView) -> Bool {
        guard needsViewportResyncAfterInteraction else { return false }
        needsViewportResyncAfterInteraction = false
        collectionView.layoutIfNeeded()
        guard let anchorItem = currentAnchorItem(in: collectionView) else { return false }
        restoreViewportAnchor(anchorItem, in: collectionView)
        return true
      }

      private func commitPendingProgrammaticItemIfNeeded(in collectionView: UICollectionView) -> Bool {
        guard let resolvedItem = engine.consumePendingProgrammaticCommit() else {
          return false
        }
        commitItemIfNeeded(resolvedItem, in: collectionView)
        return true
      }

      private func commitItemIfNeeded(_ item: ReaderViewItem, in collectionView: UICollectionView) {
        commitItem(item, in: collectionView, synchronizeViewModelImmediately: false)
      }

      private func commitItem(
        _ item: ReaderViewItem,
        in collectionView: UICollectionView,
        synchronizeViewModelImmediately: Bool
      ) {
        let commit = positionCommit(for: item)
        let previousCommittedItem = engine.committedItem
        engine.commit(item)
        preloadVisiblePages(for: item)
        refreshCommittedPlaybackState(
          from: previousCommittedItem,
          to: item,
          in: collectionView
        )
        if commit.navigationTarget != nil {
          alignWholeSpread(item, with: commit.anchor, in: collectionView)
        }
        if synchronizeViewModelImmediately {
          commitViewModelPosition(
            commit.anchor,
            matchingNavigationTarget: commit.navigationTarget
          )
        } else {
          scheduleViewModelCommit(
            for: item,
            anchor: commit.anchor,
            matchingNavigationTarget: commit.navigationTarget
          )
        }
      }

      /// Pans a committed whole spread to the edge an explicit navigation
      /// target names, e.g. a step toward its far edge.
      private func alignWholeSpread(
        _ item: ReaderViewItem,
        with anchor: ReaderPositionAnchor,
        in collectionView: UICollectionView
      ) {
        guard let edge = ReaderSpreadEdge(splitPart: anchor.preferredSplitPart),
          let index = engine.renderedItems.firstIndex(of: item),
          let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? NativePagedPageCell
        else { return }
        cell.panWholeSpread(to: edge, animated: parent.navigationAnimationDuration > 0)
      }

      /// Leaves drags a whole spread can still follow to the spread's own
      /// scroll view, so the spread pans before the page turns.
      func shouldBeginPaging(with pan: UIPanGestureRecognizer) -> Bool {
        guard let collectionView,
          let dragX = pan.horizontalDrag(in: collectionView),
          let indexPath = collectionView.indexPathForItem(at: pan.location(in: collectionView)),
          let cell = collectionView.cellForItem(at: indexPath) as? NativePagedPageCell
        else {
          return true
        }
        return !cell.canPanWholeSpread(forHorizontalDrag: dragX)
      }

      private func refreshVisibleCells(
        in collectionView: UICollectionView,
        matching pageIDs: Set<ReaderPageID>? = nil
      ) {
        for cell in collectionView.visibleCells {
          guard let indexPath = collectionView.indexPath(for: cell),
            let item = renderedItem(at: indexPath.item)
          else {
            continue
          }
          if let pageIDs, !item.pageIDs.contains(where: pageIDs.contains) {
            continue
          }
          configureCell(cell, at: indexPath.item, in: collectionView)
        }
      }

      func hasVisiblePagePresentationContent() -> Bool {
        guard let collectionView else { return false }
        return !collectionView.visibleCells.isEmpty
      }

      func applyPagePresentationInvalidation(_ invalidation: ReaderPagePresentationInvalidation) {
        guard let collectionView else { return }

        switch invalidation {
        case .all:
          refreshVisibleCells(in: collectionView)
        case .pages(let pageIDs):
          refreshVisibleCells(in: collectionView, matching: pageIDs)
        }
      }

      private func renderedItem(at index: Int) -> ReaderViewItem? {
        guard engine.renderedItems.indices.contains(index) else { return nil }
        return engine.renderedItems[index]
      }

      private func fallbackCell(
        for indexPath: IndexPath,
        in collectionView: UICollectionView
      ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: Self.pageCellReuseIdentifier,
          for: indexPath
        )
        if let pageCell = cell as? NativePagedPageCell {
          pageCell.resetContent(backgroundColor: UIColor(parent.renderConfig.readerBackground.color))
        }
        return cell
      }

      private func configureCell(
        _ cell: UICollectionViewCell,
        at index: Int,
        in collectionView: UICollectionView
      ) {
        guard let item = renderedItem(at: index) else { return }

        if item.isEnd {
          guard let endCell = cell as? NativePagedEndCell else { return }
          let segmentBookId = item.pageID.bookId
          endCell.configure(
            previousBook: parent.viewModel.endPagePreviousBook(forSegmentBookId: segmentBookId),
            nextBook: parent.viewModel.nextBook(forSegmentBookId: segmentBookId),
            readListContext: parent.readListContext,
            readingDirection: parent.readingDirection,
            renderConfig: parent.renderConfig,
            nextBookOfflineState: parent.viewModel.nextBookOfflineState(forSegmentBookId: segmentBookId),
            onDismiss: parent.onDismiss
          )
          return
        }

        guard let pageCell = cell as? NativePagedPageCell else { return }
        pageCell.backgroundColor = UIColor(parent.renderConfig.readerBackground.color)
        pageCell.configure(
          viewModel: parent.viewModel,
          item: item,
          wholeSpread: parent.viewModel.wholeSpreadPresentation(
            for: item,
            isDualPagePresentation: parent.mode.isDualPage,
            readingDirection: parent.readingDirection,
            splitWidePageMode: parent.splitWidePageMode,
            relativeTo: engine.committedItem
          ),
          screenSize: resolvedViewportSize(for: collectionView),
          renderConfig: parent.renderConfig,
          readingDirection: parent.readingDirection,
          splitWidePageMode: parent.splitWidePageMode,
          isPlaybackActive: item == engine.committedItem
        )
      }

      private func refreshCommittedPlaybackState(
        from previousItem: ReaderViewItem?,
        to currentItem: ReaderViewItem,
        in collectionView: UICollectionView
      ) {
        guard previousItem != currentItem else { return }

        for cell in collectionView.visibleCells {
          guard let indexPath = collectionView.indexPath(for: cell),
            let item = renderedItem(at: indexPath.item),
            let pageCell = cell as? NativePagedPageCell
          else {
            continue
          }

          guard item == previousItem || item == currentItem else { continue }
          pageCell.updatePlaybackActive(item == currentItem)
        }
      }

      private func positionCommit(
        for item: ReaderViewItem
      ) -> (anchor: ReaderPositionAnchor, navigationTarget: ReaderPositionAnchor?) {
        if let navigationTarget = pendingNavigationTarget,
          parent.viewModel.navigationTarget == navigationTarget,
          let navigationAnchor = strictNavigationAnchor(for: navigationTarget),
          navigationAnchor.item == item
        {
          return (navigationAnchor, navigationTarget)
        }

        let capturedAnchor = parent.viewModel.captureCurrentPositionAnchor()
        let focusedPageID =
          capturedAnchor.focusedPageID.flatMap { item.pageIDs.contains($0) ? $0 : nil }
          ?? item.pageID
        return (
          ReaderPositionAnchor(
            item: item,
            focusedPageID: focusedPageID,
            preferredSplitPart: item.preferredSplitPart(preserving: capturedAnchor)
          ),
          nil
        )
      }

      private func commitViewModelPosition(
        _ anchor: ReaderPositionAnchor,
        matchingNavigationTarget navigationTarget: ReaderPositionAnchor?
      ) {
        guard parent.viewModel.navigationTarget == navigationTarget else { return }
        if parent.viewModel.captureCurrentPositionAnchor() != anchor {
          parent.viewModel.updateCurrentPosition(anchor: anchor)
        }
        if let navigationTarget {
          clearNavigationTargetIfCurrent(navigationTarget)
        }
      }

      private func scheduleViewModelCommit(
        for item: ReaderViewItem,
        anchor: ReaderPositionAnchor? = nil,
        matchingNavigationTarget navigationTarget: ReaderPositionAnchor? = nil
      ) {
        let commit = anchor.map { ($0, navigationTarget) } ?? positionCommit(for: item)
        guard parent.viewModel.navigationTarget == commit.1 else {
          return
        }
        guard
          parent.viewModel.captureCurrentPositionAnchor() != commit.0
            || commit.1 != nil
        else {
          return
        }

        deferredViewModelCommitTask?.cancel()
        deferredViewModelCommitTask = Task { @MainActor [weak self] in
          await Task.yield()
          guard let self, self.engine.committedItem == item else { return }
          self.commitViewModelPosition(
            commit.0,
            matchingNavigationTarget: commit.1
          )
        }
      }

      private func preloadVisiblePages(for item: ReaderViewItem) {
        let visiblePageIDs = item.pageIDs
        if visiblePreloadItem == item,
          visiblePreloadTask != nil
            || visiblePageIDs.allSatisfy({
              parent.viewModel.preloadedImage(for: $0) != nil
                || parent.viewModel.hasPendingImageLoad(for: $0)
            })
        {
          return
        }

        parent.viewModel.prioritizeVisiblePageLoads(for: visiblePageIDs)

        visiblePreloadTask?.cancel()
        visiblePreloadItem = item
        let viewModel = parent.viewModel
        visiblePreloadTask = Task(priority: .userInitiated) { @MainActor [weak self] in
          defer {
            if let self, self.visiblePreloadItem == item {
              self.visiblePreloadTask = nil
            }
          }

          for pageID in visiblePageIDs {
            guard !Task.isCancelled else { return }
            _ = await viewModel.preloadImage(for: pageID)
          }
        }
      }

      private func handleApplicationWillResignActive() {
        guard let collectionView else { return }

        collectionView.layoutIfNeeded()
        clearProgrammaticScrollState()
        needsViewportResyncAfterInteraction = false
        pendingUserInteractionTargetItem = nil

        guard let item = centeredItem(in: collectionView) ?? engine.committedItem else { return }
        commitItem(item, in: collectionView, synchronizeViewModelImmediately: true)
      }

      private func finishScrollInteractionIfNeeded() {
        guard let collectionView else { return }

        let interactionTargetItem =
          pendingUserInteractionTargetItem.flatMap { engine.resolveItem($0) } ?? pendingUserInteractionTargetItem
        let appliedQueuedItems = applyQueuedRenderedItemsIfNeeded(
          in: collectionView,
          anchorFallback: interactionTargetItem,
          preferAnchorFallback: interactionTargetItem != nil
        )
        let restoredViewport = finalizeDeferredViewportResyncIfNeeded(in: collectionView)
        if !appliedQueuedItems, !restoredViewport, parent.viewModel.navigationTarget == nil {
          if let interactionTargetItem {
            commitItemIfNeeded(interactionTargetItem, in: collectionView)
          } else {
            commitCenteredItem(in: collectionView)
          }
        }
        pendingUserInteractionTargetItem = nil
      }

      private func finishProgrammaticScroll(in collectionView: UICollectionView) {
        guard engine.isProgrammaticScrolling || engine.hasPendingProgrammaticCommit else {
          return
        }

        let programmaticTargetItem = engine.programmaticTargetItem
        pendingProgrammaticTargetOffset = nil
        _ = engine.endProgrammaticScroll()
        let appliedQueuedItems = applyQueuedRenderedItemsIfNeeded(
          in: collectionView,
          anchorFallback: programmaticTargetItem,
          preferAnchorFallback: true
        )
        let committedPendingItem = commitPendingProgrammaticItemIfNeeded(in: collectionView)
        let restoredViewport = finalizeDeferredViewportResyncIfNeeded(in: collectionView)
        if !committedPendingItem {
          if !appliedQueuedItems, !restoredViewport, parent.viewModel.navigationTarget == nil {
            commitCenteredItem(in: collectionView)
          }
        }
      }

      func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
      }

      func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        engine.renderedItems.count
      }

      func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
      ) -> UICollectionViewCell {
        guard let item = renderedItem(at: indexPath.item) else {
          return fallbackCell(for: indexPath, in: collectionView)
        }

        if item.isEnd {
          let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.endCellReuseIdentifier,
            for: indexPath
          )
          configureCell(cell, at: indexPath.item, in: collectionView)
          return cell
        }

        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: Self.pageCellReuseIdentifier,
          for: indexPath
        )
        configureCell(cell, at: indexPath.item, in: collectionView)
        return cell
      }

      func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
      ) {
        pagePresentationCoordinator.flushIfPossible()
      }

      func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
      ) -> CGSize {
        resolvedViewportSize(for: collectionView)
      }

      @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let collectionView else { return }
        guard !isTapZoneSuppressed(in: collectionView) else { return }

        let location = gesture.location(in: collectionView)
        dispatchTapZoneTap(at: location, in: collectionView)
      }

      @objc func handleDoubleTap(_: UITapGestureRecognizer) {}

      @objc func handleLongPress(_: UILongPressGestureRecognizer) {}

      private func isScrollInteractionActive(in collectionView: UICollectionView) -> Bool {
        collectionView.isDragging || collectionView.isDecelerating || collectionView.isTracking
      }

      private func isTapZoneSuppressed(in collectionView: UICollectionView) -> Bool {
        parent.viewModel.isZoomed
          || collectionView.isDragging
          || collectionView.isDecelerating
          || collectionView.isTracking
      }

      private func dispatchTapZoneTap(at location: CGPoint, in collectionView: UICollectionView) {
        guard !isTapZoneSuppressed(in: collectionView) else { return }

        let visibleBounds = collectionView.bounds
        guard visibleBounds.width > 0, visibleBounds.height > 0 else { return }
        let normalizedX = min(max((location.x - visibleBounds.minX) / visibleBounds.width, 0), 1)
        let normalizedY = min(max((location.y - visibleBounds.minY) / visibleBounds.height, 0), 1)
        parent.onTapZoneTap(normalizedX, normalizedY)
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view?.hasInteractiveAncestor != true
      }

      func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingUserInteractionTargetItem = nil
        cancelProgrammaticNavigationIfNeeded()
      }

      func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
      ) {
        guard let collectionView else { return }
        pendingUserInteractionTargetItem = resolvedSwipeTargetItem(
          for: targetContentOffset.pointee,
          in: collectionView
        )
      }

      func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let collectionView else { return }
        if let item = centeredItem(in: collectionView) {
          preloadVisiblePages(for: item)
        }
      }

      func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard collectionView != nil else { return }
        if !decelerate {
          finishScrollInteractionIfNeeded()
        }
      }

      func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard collectionView != nil else { return }
        finishScrollInteractionIfNeeded()
      }

      func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard let collectionView else { return }
        finishProgrammaticScroll(in: collectionView)
      }
    }
  }
#endif
