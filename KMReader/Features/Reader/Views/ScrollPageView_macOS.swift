#if os(macOS)
  import AppKit
  import SwiftUI

  struct ScrollPageView: NSViewRepresentable {
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

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
      let layout = NSCollectionViewFlowLayout()
      layout.scrollDirection = mode.isVertical ? .vertical : .horizontal
      layout.minimumLineSpacing = 0
      layout.minimumInteritemSpacing = 0

      let collectionView = NativePagedLayoutAwareCollectionView()
      collectionView.collectionViewLayout = layout
      collectionView.delegate = context.coordinator
      collectionView.dataSource = context.coordinator
      collectionView.backgroundColors = [NSColor(renderConfig.readerBackground.color)]
      collectionView.isSelectable = false
      collectionView.userInterfaceLayoutDirection = .leftToRight
      collectionView.register(
        NativePagedPageCell.self,
        forItemWithIdentifier: NSUserInterfaceItemIdentifier(Coordinator.pageCellReuseIdentifier)
      )
      collectionView.register(
        NativePagedEndCell.self,
        forItemWithIdentifier: NSUserInterfaceItemIdentifier(Coordinator.endCellReuseIdentifier)
      )

      let scrollView = NSScrollView()
      scrollView.documentView = collectionView
      scrollView.hasVerticalScroller = false
      scrollView.hasHorizontalScroller = false
      scrollView.backgroundColor = NSColor(renderConfig.readerBackground.color)
      scrollView.drawsBackground = true
      scrollView.contentView.postsBoundsChangedNotifications = true

      let clickGesture = NSClickGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleClick(_:))
      )
      clickGesture.numberOfClicksRequired = 1
      clickGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(clickGesture)

      let doubleClickGesture = NSClickGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDoubleClick(_:))
      )
      doubleClickGesture.numberOfClicksRequired = 2
      doubleClickGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(doubleClickGesture)

      let longPressGesture = NSPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(longPressGesture)
      context.coordinator.longPressGesture = longPressGesture

      collectionView.frame = CGRect(origin: .zero, size: scrollView.contentView.bounds.size)
      collectionView.autoresizingMask = [.width, .height]

      context.coordinator.scrollView = scrollView
      context.coordinator.collectionView = collectionView
      context.coordinator.installObservers()
      collectionView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleCollectionViewLayout()
      }

      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let collectionView = scrollView.documentView as? NSCollectionView else { return }

      collectionView.backgroundColors = [NSColor(renderConfig.readerBackground.color)]
      collectionView.userInterfaceLayoutDirection = .leftToRight

      if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
        let targetDirection: NSCollectionView.ScrollDirection = mode.isVertical ? .vertical : .horizontal
        if layout.scrollDirection != targetDirection {
          layout.scrollDirection = targetDirection
          layout.invalidateLayout()
        }
      }

      context.coordinator.update(parent: self, scrollView: scrollView, collectionView: collectionView)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
      coordinator.synchronizeCurrentPositionBeforeTeardown(in: nsView)
      coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout,
      NSGestureRecognizerDelegate, NativePagedPagePresentationHost
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
      weak var scrollView: NSScrollView?
      weak var collectionView: NSCollectionView?

      private let engine = ScrollReaderEngine()
      private let pagePresentationCoordinator = NativePagedPagePresentationCoordinator()
      private var isAdjustingBounds = false
      private var lastViewportSize: CGSize = .zero
      private var observersInstalled = false
      private var lastRenderInputs: RenderInputs?
      private var deferredViewModelCommitTask: Task<Void, Never>?
      private var visiblePreloadTask: Task<Void, Never>?
      private var visiblePreloadItem: ReaderViewItem?
      private var programmaticScrollToken: Int = 0
      private var lastObservedClipBounds: CGRect = .zero
      private var pendingNavigationTarget: ReaderPositionAnchor?
      private var singleClickWorkItem: DispatchWorkItem?
      weak var longPressGesture: NSPressGestureRecognizer?

      init(_ parent: ScrollPageView) {
        self.parent = parent
        super.init()
        pagePresentationCoordinator.host = self
      }

      func installObservers() {
        guard !observersInstalled, let scrollView else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleBoundsDidChange(_:)),
          name: NSView.boundsDidChangeNotification,
          object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleDidEndLiveScroll(_:)),
          name: NSScrollView.didEndLiveScrollNotification,
          object: scrollView
        )
      }

      func teardown() {
        NotificationCenter.default.removeObserver(self)
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
        deferredViewModelCommitTask?.cancel()
        deferredViewModelCommitTask = nil
        visiblePreloadTask?.cancel()
        visiblePreloadTask = nil
        visiblePreloadItem = nil
        pendingNavigationTarget = nil
        pagePresentationCoordinator.teardown()
        engine.teardown()
      }

      func synchronizeCurrentPositionBeforeTeardown(in scrollView: NSScrollView) {
        deferredViewModelCommitTask?.cancel()
        deferredViewModelCommitTask = nil

        guard let collectionView = scrollView.documentView as? NSCollectionView else { return }
        collectionView.layoutSubtreeIfNeeded()

        guard let item = currentAnchorItem(in: scrollView, collectionView: collectionView) else {
          return
        }
        synchronizeViewModelCurrentPosition(to: item)
      }

      func update(
        parent: ScrollPageView,
        scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) {
        self.parent = parent
        self.scrollView = scrollView
        self.collectionView = collectionView
        installObservers()
        pagePresentationCoordinator.update(viewModel: parent.viewModel)

        let displayedItems = parent.mode.displayOrderedItems(parent.viewModel.viewItems)
        let anchorItem = currentAnchorItem(in: scrollView, collectionView: collectionView)
        let sizeChanged = updateLayoutIfNeeded(for: collectionView)
        let renderInputsChanged = updateRenderInputsIfNeeded()
        var frameChanged = synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView)
        var refreshedVisibleContent = false

        if engine.installInitialItemsIfNeeded(displayedItems) {
          collectionView.reloadData()
          collectionView.layoutSubtreeIfNeeded()
          frameChanged =
            synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView)
            || frameChanged
          refreshedVisibleContent = synchronizeInitialPositionIfPossible(
            in: scrollView,
            collectionView: collectionView
          )
        } else if displayedItems != engine.renderedItems {
          if engine.isInteractionActive {
            engine.queueRenderedItems(displayedItems, anchor: anchorItem)
          } else {
            // A rebuild restores from the committed position: the view model's
            // resolution is split-side aware, the engine's stale items are not.
            applyRenderedItems(
              displayedItems,
              anchor: parent.viewModel.currentViewItem() ?? anchorItem,
              commitAfterRestore: parent.viewModel.navigationTarget == nil,
              in: scrollView,
              collectionView: collectionView
            )
          }
          refreshedVisibleContent = true
        }

        if engine.hasSyncedInitialPosition, sizeChanged || frameChanged, !refreshedVisibleContent {
          if let anchorItem {
            _ = scrollToItem(anchorItem, animated: false, in: scrollView, collectionView: collectionView)
            refreshVisibleItems(in: collectionView)
            if parent.viewModel.navigationTarget == nil {
              commitItemIfNeeded(anchorItem, in: collectionView)
            }
            refreshedVisibleContent = true
          }
        }

        if let navigationTarget = parent.viewModel.navigationTarget {
          handleNavigationChange(navigationTarget, in: scrollView, collectionView: collectionView)
        } else if renderInputsChanged && !refreshedVisibleContent {
          refreshVisibleItems(in: collectionView)
        }

        pagePresentationCoordinator.flushIfPossible()
        lastObservedClipBounds = scrollView.contentView.bounds
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

      private func updateLayoutIfNeeded(for collectionView: NSCollectionView) -> Bool {
        let viewportSize = resolvedViewportSize(for: collectionView)
        guard viewportSize.width > 0, viewportSize.height > 0 else { return false }

        let sizeChanged = viewportSize != lastViewportSize
        lastViewportSize = viewportSize

        if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout,
          layout.itemSize != viewportSize
        {
          layout.itemSize = viewportSize
          layout.invalidateLayout()
        }

        return sizeChanged
      }

      private func resolvedViewportSize(for collectionView: NSCollectionView) -> CGSize {
        if let scrollView {
          let clipBoundsSize = scrollView.contentView.bounds.size
          // The document view can grow beyond the visible page viewport, so page sizing
          // must track the clip view instead of the collection view frame.
          if clipBoundsSize.width > 0, clipBoundsSize.height > 0 {
            return clipBoundsSize
          }
        }
        if parent.viewportSize.width > 0, parent.viewportSize.height > 0 {
          return parent.viewportSize
        }
        return collectionView.bounds.size
      }

      private func synchronizeCollectionViewFrame(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        let viewportSize = resolvedViewportSize(for: collectionView)
        guard viewportSize.width > 0, viewportSize.height > 0 else { return false }

        let contentSize =
          collectionView.collectionViewLayout?.collectionViewContentSize
          ?? viewportSize
        let desiredSize = CGSize(
          width: max(
            parent.mode.isVertical ? viewportSize.width : contentSize.width,
            scrollView.contentView.bounds.width
          ),
          height: max(
            parent.mode.isVertical ? contentSize.height : viewportSize.height,
            scrollView.contentView.bounds.height
          )
        )
        guard collectionView.frame.size != desiredSize else { return false }

        collectionView.setFrameSize(desiredSize)
        return true
      }

      private func canApplyInitialPosition(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        let viewportSize = resolvedViewportSize(for: collectionView)
        let clipBounds = scrollView.contentView.bounds.size
        return scrollView.window != nil
          && max(viewportSize.width, clipBounds.width) > 0
          && max(viewportSize.height, clipBounds.height) > 0
      }

      @discardableResult
      private func synchronizeInitialPositionIfPossible(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        guard
          let currentItem = engine.prepareInitialPosition(
            anchor: parent.viewModel.captureCurrentPositionAnchor()
          )
        else {
          return false
        }
        guard canApplyInitialPosition(in: scrollView, collectionView: collectionView) else { return false }
        _ = synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView)

        guard scrollToItem(currentItem, animated: false, in: scrollView, collectionView: collectionView)
        else {
          return false
        }
        guard let committedItem = engine.completeInitialPosition() else { return false }
        preloadVisiblePages(for: committedItem)
        refreshVisibleItems(in: collectionView)
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
        guard let scrollView, let collectionView else { return }
        _ = synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView)
        if synchronizeInitialPositionIfPossible(in: scrollView, collectionView: collectionView) {
          pagePresentationCoordinator.flushIfPossible()
        }
      }

      private func applyRenderedItems(
        _ items: [ReaderViewItem],
        anchor: ReaderViewItem?,
        commitAfterRestore: Bool,
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) {
        engine.replaceRenderedItems(items)
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
        _ = synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView)

        if let anchor = engine.resolveItem(anchor) {
          _ = scrollToItem(anchor, animated: false, in: scrollView, collectionView: collectionView)
        }

        refreshVisibleItems(in: collectionView)
        if commitAfterRestore {
          commitRestoredItemIfNeeded(
            anchor: anchor,
            in: scrollView,
            collectionView: collectionView
          )
        }
      }

      @discardableResult
      private func applyQueuedRenderedItemsIfNeeded(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        guard
          let update = engine.consumeQueuedRenderedItems(
            anchorFallback: currentAnchorItem(in: scrollView, collectionView: collectionView)
          )
        else {
          return false
        }

        applyRenderedItems(
          update.items,
          anchor: update.anchor,
          commitAfterRestore: parent.viewModel.navigationTarget == nil,
          in: scrollView,
          collectionView: collectionView
        )
        return true
      }

      private func handleNavigationChange(
        _ navigationTarget: ReaderPositionAnchor,
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) {
        // While the user is in the middle of a swipe (drag or its deceleration), ignore
        // tap-initiated navigation. The drag's intent dominates; layering a programmatic
        // scroll over natural deceleration produces a double page advance. Mirrors the
        // existing guard in `scrollViewWillBeginDragging` that lets a drag override an
        // in-flight programmatic scroll.
        if engine.isUserInteracting {
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
          refreshVisibleItems(in: collectionView)
          return
        }

        if centeredItem(in: scrollView, collectionView: collectionView) == targetItem {
          engine.clearPendingProgrammaticCommit()
          commitItemIfNeeded(targetItem, in: collectionView)
          return
        }

        _ = scrollToItem(targetItem, animated: true, in: scrollView, collectionView: collectionView)
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
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        guard let index = engine.renderedItems.firstIndex(of: item) else { return false }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutSubtreeIfNeeded()

        guard
          let attributes = collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath)
        else {
          return false
        }

        let targetOrigin = clampedContentOrigin(
          CGPoint(
            x: parent.mode.isVertical ? scrollView.contentView.bounds.origin.x : attributes.frame.minX,
            y: parent.mode.isVertical ? attributes.frame.minY : scrollView.contentView.bounds.origin.y
          ),
          in: scrollView,
          collectionView: collectionView
        )

        if isEquivalentContentOrigin(targetOrigin, to: scrollView.contentView.bounds.origin) {
          guard isPositionedOnItem(item, in: scrollView, collectionView: collectionView) else {
            return false
          }
          engine.clearPendingProgrammaticCommit()
          refreshVisibleItems(in: collectionView)
          if animated {
            commitItemIfNeeded(item, in: collectionView)
          }
          return true
        }

        let shouldAnimate = animated && parent.navigationAnimationDuration > 0
        programmaticScrollToken &+= 1
        let token = programmaticScrollToken

        if shouldAnimate {
          engine.beginProgrammaticScroll(to: item)
          NSAnimationContext.runAnimationGroup { context in
            context.duration = parent.navigationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
          } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
              guard let self, token == self.programmaticScrollToken else { return }
              self.lastObservedClipBounds = scrollView.contentView.bounds
              self.finishProgrammaticScroll(in: scrollView, collectionView: collectionView)
            }
          }
        } else {
          engine.clearPendingProgrammaticCommit()
          isAdjustingBounds = true
          scrollView.contentView.setBoundsOrigin(targetOrigin)
          scrollView.reflectScrolledClipView(scrollView.contentView)
          isAdjustingBounds = false
          lastObservedClipBounds = scrollView.contentView.bounds
          collectionView.layoutSubtreeIfNeeded()
          guard isPositionedOnItem(item, in: scrollView, collectionView: collectionView) else {
            return false
          }
          refreshVisibleItems(in: collectionView)
          if animated {
            commitItemIfNeeded(item, in: collectionView)
          }
        }
        return true
      }

      private func clampedContentOrigin(
        _ proposedOrigin: CGPoint,
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> CGPoint {
        let contentSize =
          collectionView.collectionViewLayout?.collectionViewContentSize
          ?? collectionView.bounds.size
        let maxX = max(0, contentSize.width - scrollView.contentView.bounds.width)
        let maxY = max(0, contentSize.height - scrollView.contentView.bounds.height)

        return CGPoint(
          x: min(max(proposedOrigin.x, 0), maxX),
          y: min(max(proposedOrigin.y, 0), maxY)
        )
      }

      private func isEquivalentContentOrigin(_ lhs: CGPoint, to rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
      }

      private func currentAnchorItem(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> ReaderViewItem? {
        centeredItem(in: scrollView, collectionView: collectionView)
          ?? parent.viewModel.currentViewItem()
          ?? engine.committedItem
      }

      private func isPositionedOnItem(
        _ item: ReaderViewItem,
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> Bool {
        centeredItem(in: scrollView, collectionView: collectionView) == item
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

      private func centeredItem(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) -> ReaderViewItem? {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        guard !visibleIndexPaths.isEmpty else { return engine.committedItem }

        let visibleRect = scrollView.contentView.bounds
        let center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)

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
        in collectionView: NSCollectionView
      ) -> CGFloat {
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
          return .greatestFiniteMagnitude
        }
        let frame = attributes.frame
        let dx = frame.midX - center.x
        let dy = frame.midY - center.y
        return sqrt(dx * dx + dy * dy)
      }

      private func commitCenteredItem(in collectionView: NSCollectionView) {
        guard let scrollView,
          let item = centeredItem(in: scrollView, collectionView: collectionView)
        else {
          return
        }
        commitItemIfNeeded(item, in: collectionView)
      }

      private func commitRestoredItemIfNeeded(
        anchor: ReaderViewItem?,
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) {
        if let item = engine.resolveItem(anchor) {
          commitItemIfNeeded(item, in: collectionView)
          return
        }
        if let item = centeredItem(in: scrollView, collectionView: collectionView) {
          commitItemIfNeeded(item, in: collectionView)
        }
      }

      private func commitPendingProgrammaticItemIfNeeded(in collectionView: NSCollectionView) -> Bool {
        guard let resolvedItem = engine.consumePendingProgrammaticCommit() else {
          return false
        }
        commitItemIfNeeded(resolvedItem, in: collectionView)
        return true
      }

      private func commitItemIfNeeded(_ item: ReaderViewItem, in collectionView: NSCollectionView) {
        let commit = positionCommit(for: item)
        let previousCommittedItem = engine.committedItem
        engine.commit(item)
        preloadVisiblePages(for: item)
        refreshCommittedPlaybackState(
          from: previousCommittedItem,
          to: item,
          in: collectionView
        )
        scheduleViewModelCommit(
          for: item,
          anchor: commit.anchor,
          matchingNavigationTarget: commit.navigationTarget
        )
      }

      private func refreshVisibleItems(
        in collectionView: NSCollectionView,
        matching pageIDs: Set<ReaderPageID>? = nil
      ) {
        for item in collectionView.visibleItems() {
          let index = item.representedObject as? Int ?? -1
          guard let viewItem = renderedItem(at: index) else { continue }
          if let pageIDs, !viewItem.pageIDs.contains(where: pageIDs.contains) {
            continue
          }
          configureItem(item, at: index, in: collectionView)
        }
      }

      func hasVisiblePagePresentationContent() -> Bool {
        guard let collectionView else { return false }
        return !collectionView.visibleItems().isEmpty
      }

      private func finishProgrammaticScroll(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView
      ) {
        _ = engine.endProgrammaticScroll()
        let appliedQueuedItems = applyQueuedRenderedItemsIfNeeded(
          in: scrollView,
          collectionView: collectionView
        )
        if !commitPendingProgrammaticItemIfNeeded(in: collectionView) {
          if !appliedQueuedItems, parent.viewModel.navigationTarget == nil {
            commitCenteredItem(in: collectionView)
          }
        }
      }

      private func snapToNearestItemIfNeeded(
        in scrollView: NSScrollView,
        collectionView: NSCollectionView,
        animated: Bool
      ) {
        guard let item = centeredItem(in: scrollView, collectionView: collectionView) else { return }
        _ = scrollToItem(item, animated: animated, in: scrollView, collectionView: collectionView)
      }

      func applyPagePresentationInvalidation(_ invalidation: ReaderPagePresentationInvalidation) {
        guard let collectionView else { return }

        switch invalidation {
        case .all:
          refreshVisibleItems(in: collectionView)
        case .pages(let pageIDs):
          refreshVisibleItems(in: collectionView, matching: pageIDs)
        }
      }

      private func renderedItem(at index: Int) -> ReaderViewItem? {
        guard engine.renderedItems.indices.contains(index) else { return nil }
        return engine.renderedItems[index]
      }

      private func fallbackItem(
        for indexPath: IndexPath,
        in collectionView: NSCollectionView
      ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
          withIdentifier: NSUserInterfaceItemIdentifier(Self.pageCellReuseIdentifier),
          for: indexPath
        )
        if let pageCell = item as? NativePagedPageCell {
          pageCell.resetContent(backgroundColor: NSColor(parent.renderConfig.readerBackground.color))
        }
        return item
      }

      private func configureItem(
        _ item: NSCollectionViewItem,
        at index: Int,
        in collectionView: NSCollectionView
      ) {
        guard let viewItem = renderedItem(at: index) else { return }
        item.representedObject = index

        if viewItem.isEnd {
          guard let endItem = item as? NativePagedEndCell else { return }
          let segmentBookId = viewItem.pageID.bookId
          endItem.configure(
            previousBook: parent.viewModel.endPagePreviousBook(forSegmentBookId: segmentBookId),
            nextBook: parent.viewModel.nextBook(forSegmentBookId: segmentBookId),
            readListContext: parent.readListContext,
            readingDirection: parent.readingDirection,
            renderConfig: parent.renderConfig,
            nextBookOfflineState: parent.viewModel.nextBookOfflineState(forSegmentBookId: segmentBookId),
            remainingUnreadCount: parent.viewModel.remainingUnreadCount(forSegmentBookId: segmentBookId),
            onDismiss: parent.onDismiss
          )
          return
        }

        guard let pageItem = item as? NativePagedPageCell else { return }
        pageItem.view.layer?.backgroundColor = NSColor(parent.renderConfig.readerBackground.color).cgColor
        pageItem.configure(
          viewModel: parent.viewModel,
          item: viewItem,
          screenSize: resolvedViewportSize(for: collectionView),
          renderConfig: parent.renderConfig,
          readingDirection: parent.readingDirection,
          splitWidePageMode: parent.splitWidePageMode,
          isPlaybackActive: viewItem == engine.committedItem
        )
      }

      private func refreshCommittedPlaybackState(
        from previousItem: ReaderViewItem?,
        to currentItem: ReaderViewItem,
        in collectionView: NSCollectionView
      ) {
        guard previousItem != currentItem else { return }

        for item in collectionView.visibleItems() {
          let index = item.representedObject as? Int ?? -1
          guard let viewItem = renderedItem(at: index),
            let pageItem = item as? NativePagedPageCell
          else {
            continue
          }

          guard viewItem == previousItem || viewItem == currentItem else { continue }
          pageItem.updatePlaybackActive(viewItem == currentItem)
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

      @objc private func handleBoundsDidChange(_ notification: Notification) {
        guard let scrollView, let collectionView else { return }
        let currentBounds = scrollView.contentView.bounds
        let previousBounds = lastObservedClipBounds
        let anchorItem = currentAnchorItem(in: scrollView, collectionView: collectionView)
        lastObservedClipBounds = currentBounds

        guard !isAdjustingBounds, !engine.isProgrammaticScrolling else { return }

        let originChanged = previousBounds.origin != currentBounds.origin
        let sizeChanged =
          previousBounds.size != .zero
          && previousBounds.size != currentBounds.size

        if sizeChanged {
          collectionView.layoutSubtreeIfNeeded()
          if synchronizeCollectionViewFrame(in: scrollView, collectionView: collectionView) {
            collectionView.layoutSubtreeIfNeeded()
          }

          if engine.hasSyncedInitialPosition, let anchorItem {
            _ = scrollToItem(anchorItem, animated: false, in: scrollView, collectionView: collectionView)
            refreshVisibleItems(in: collectionView)
            if parent.viewModel.navigationTarget == nil {
              commitItemIfNeeded(anchorItem, in: collectionView)
            }
          } else if synchronizeInitialPositionIfPossible(in: scrollView, collectionView: collectionView) {
            pagePresentationCoordinator.flushIfPossible()
          }
          return
        }

        if originChanged {
          _ = engine.beginUserInteraction()
        }
      }

      @objc private func handleDidEndLiveScroll(_ notification: Notification) {
        guard let scrollView, let collectionView else { return }

        _ = engine.endUserInteraction()
        engine.clearPendingProgrammaticCommit()
        let appliedQueuedItems = applyQueuedRenderedItemsIfNeeded(
          in: scrollView,
          collectionView: collectionView
        )
        if !appliedQueuedItems, parent.viewModel.navigationTarget == nil {
          snapToNearestItemIfNeeded(in: scrollView, collectionView: collectionView, animated: true)
        }
      }

      @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
        singleClickWorkItem?.cancel()
        guard gesture.state == .ended else { return }
        guard let scrollView else { return }
        guard !isTapZoneSuppressed(in: scrollView) else { return }

        let location = gesture.location(in: scrollView)
        guard !isInteractiveElement(at: location, in: scrollView) else { return }
        let workItem = DispatchWorkItem { [weak self, weak scrollView] in
          guard let self, let scrollView else { return }
          self.dispatchTapZoneTap(at: location, in: scrollView)
        }
        singleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
      }

      @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
      }

      @objc func handleLongPress(_: NSPressGestureRecognizer) {}

      private func isTapZoneSuppressed(in scrollView: NSScrollView) -> Bool {
        parent.viewModel.isZoomed
          || isAdjustingBounds
          || engine.isUserInteracting
      }

      private func dispatchTapZoneTap(
        at location: CGPoint,
        in scrollView: NSScrollView
      ) {
        singleClickWorkItem = nil
        guard !isTapZoneSuppressed(in: scrollView) else { return }

        let bounds = scrollView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let normalizedX = min(max(location.x / bounds.width, 0), 1)
        let normalizedY = min(max(1 - (location.y / bounds.height), 0), 1)
        parent.onTapZoneTap(normalizedX, normalizedY)
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        // Clicks/presses landing on interactive elements (e.g. the end card's
        // Close button) must reach the control, not the tap-zone recognizers.
        if gestureRecognizer is NSClickGestureRecognizer || gestureRecognizer is NSPressGestureRecognizer,
          let scrollView,
          isInteractiveElement(at: gestureRecognizer.location(in: scrollView), in: scrollView)
        {
          return false
        }
        return true
      }

      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
      ) -> Bool {
        gestureRecognizer is NSClickGestureRecognizer && otherGestureRecognizer === longPressGesture
      }

      private func isInteractiveElement(at location: CGPoint, in scrollView: NSScrollView) -> Bool {
        let contentLocation = scrollView.contentView.convert(location, from: scrollView)
        return scrollView.contentView.hitTest(contentLocation)?.hasInteractiveAncestor == true
      }

      func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
      }

      func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        engine.renderedItems.count
      }

      func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
      ) -> NSCollectionViewItem {
        guard let renderedItem = renderedItem(at: indexPath.item) else {
          return fallbackItem(for: indexPath, in: collectionView)
        }
        let identifier = NSUserInterfaceItemIdentifier(
          renderedItem.isEnd
            ? Self.endCellReuseIdentifier : Self.pageCellReuseIdentifier
        )
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
        configureItem(item, at: indexPath.item, in: collectionView)
        return item
      }

      func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
      ) {
        pagePresentationCoordinator.flushIfPossible()
      }

      func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
      ) -> CGSize {
        resolvedViewportSize(for: collectionView)
      }
    }
  }
#endif
