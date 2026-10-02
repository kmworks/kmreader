//
// CurlDualPageView.swift
//

#if os(iOS)
  import Foundation
  import SwiftUI
  import UIKit

  struct CurlDualPageView: UIViewControllerRepresentable {
    @Bindable var viewModel: ReaderViewModel
    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let animateTapTurns: Bool
    let renderConfig: ReaderRenderConfig
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    private enum SpreadSlot: Int {
      case first = 0
      case second = 1
    }

    private enum SlotContent {
      case page(pageID: ReaderPageID, splitMode: PageSplitMode)
      case end(segmentBookId: String)
      case placeholder
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
      let options: [UIPageViewController.OptionsKey: Any] = [
        .spineLocation: NSNumber(value: UIPageViewController.SpineLocation.mid.rawValue)
      ]
      let pageVC = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: options
      )
      context.coordinator.pageViewController = pageVC
      pageVC.dataSource = context.coordinator
      pageVC.delegate = context.coordinator
      context.coordinator.installTapRecognizers(on: pageVC.view)

      for recognizer in pageVC.gestureRecognizers {
        recognizer.delegate = context.coordinator
        if recognizer is UIPanGestureRecognizer {
          recognizer.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handlePagePanGesture(_:))
          )
        }
        if recognizer is UITapGestureRecognizer {
          recognizer.isEnabled = false
        }
      }

      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )

      let initialSpreadIndex = context.coordinator.currentResolvedSpreadIndex() ?? 0

      if let initialPair = context.coordinator.pageControllerPair(for: initialSpreadIndex) {
        PageCurlControllerPlanner.safeSetViewControllers(
          initialPair,
          on: pageVC,
          direction: .forward,
          animated: false
        )
      } else {
        PageCurlControllerPlanner.safeSetViewControllers(
          PageCurlControllerPlanner.placeholderControllers(
            in: pageVC,
            backgroundColor: UIColor(renderConfig.readerBackground.color)
          ),
          on: pageVC,
          direction: .forward,
          animated: false
        )
      }

      return pageVC
    }

    static func dismantleUIViewController(
      _ pageViewController: UIPageViewController,
      coordinator: Coordinator
    ) {
      coordinator.teardown(pageViewController: pageViewController)
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
      context.coordinator.parent = self
      context.coordinator.pageViewController = pageVC
      context.coordinator.updateViewModelObservation(viewModel)
      context.coordinator.applyDoubleTapRecognizerState()
      defer { context.coordinator.hasCompletedInitialUpdate = true }

      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )

      context.coordinator.syncCurrentItemWithVisibleController()
      let didViewItemsChange = context.coordinator.updateViewItemsSnapshot(
        PageCurlViewItemsSnapshot(items: viewModel.viewItems),
        preferredAnchor: viewModel.captureCurrentPositionAnchor()
      )
      guard !context.coordinator.isTransitioning, !context.coordinator.isPanGestureActive else { return }
      context.coordinator.refreshVisibleControllerConfiguration()
      context.coordinator.processNavigationTarget(
        on: pageVC,
        restoreModelPosition: didViewItemsChange
      )
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
      UIGestureRecognizerDelegate
    {
      var parent: CurlDualPageView
      var currentItem: ReaderViewItem?
      weak var pageViewController: UIPageViewController?
      var isTransitioning = false
      var hasCompletedInitialUpdate = false
      private var isActive = true
      private weak var doubleTapRecognizer: UITapGestureRecognizer?
      private var installedTapRecognizers: [UIGestureRecognizer] = []
      private var transitionTargetItem: ReaderViewItem?
      private var viewItemsSnapshot: PageCurlViewItemsSnapshot
      private var pendingViewItemsSnapshot: PageCurlViewItemsSnapshot?
      private let controllerIdentities =
        NSMapTable<UIViewController, PageCurlControllerIdentity>.weakToStrongObjects()
      private var transitionToken = 0
      private var preloadTask: Task<Void, Never>?
      private var navigationContinuationTask: Task<Void, Never>?
      private var consumedNavigationTarget: ReaderPositionAnchor?
      private var retriedNavigationTarget: ReaderPositionAnchor?
      private var programmaticTransitionToken: Int?
      private var programmaticTargetItem: ReaderViewItem?
      private var transitionWatchdogTask: Task<Void, Never>?
      private weak var observedViewModel: ReaderViewModel?
      private var pagePresentationObserverToken: UUID?

      init(_ parent: CurlDualPageView) {
        self.parent = parent
        let snapshot = PageCurlViewItemsSnapshot(items: parent.viewModel.viewItems)
        self.viewItemsSnapshot = snapshot
        self.currentItem = snapshot.resolvedItem(for: parent.viewModel.captureCurrentPositionAnchor())
      }

      func installTapRecognizers(on view: UIView) {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = self
        view.addGestureRecognizer(singleTap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(doubleTap)
        doubleTapRecognizer = doubleTap

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        singleTap.require(toFail: longPress)
        view.addGestureRecognizer(longPress)
        installedTapRecognizers = [singleTap, doubleTap, longPress]
        applyDoubleTapRecognizerState()
      }

      func applyDoubleTapRecognizerState() {
        doubleTapRecognizer?.isEnabled = parent.renderConfig.doubleTapZoomMode.isEnabled
      }

      private var totalSpreads: Int {
        viewItemsSnapshot.count
      }

      // UIKit fires willTransitionTo only once a curl actually starts, so a
      // programmatic setViewControllers landing during the pan's
      // pre-transition window corrupts the gesture and crashes the next
      // _handlePanGesture validation. Treat an active pan like a transition.
      fileprivate var isPanGestureActive: Bool {
        pageViewController?.gestureRecognizers.contains { recognizer in
          guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
          return pan.state == .began || pan.state == .changed
        } ?? false
      }

      @discardableResult
      func updateViewItemsSnapshot(
        _ snapshot: PageCurlViewItemsSnapshot,
        preferredAnchor: ReaderPositionAnchor
      ) -> Bool {
        guard snapshot != viewItemsSnapshot else {
          pendingViewItemsSnapshot = nil
          return false
        }
        guard !isTransitioning, !isPanGestureActive else {
          pendingViewItemsSnapshot = snapshot
          return false
        }
        return applyViewItemsSnapshot(snapshot, preferredAnchor: preferredAnchor)
      }

      private func applyViewItemsSnapshot(
        _ snapshot: PageCurlViewItemsSnapshot,
        preferredAnchor: ReaderPositionAnchor
      ) -> Bool {
        guard snapshot != viewItemsSnapshot else { return false }
        viewItemsSnapshot = snapshot
        currentItem = snapshot.resolvedItem(for: preferredAnchor)
        return true
      }

      @discardableResult
      private func applyPendingViewItemsSnapshot(preferredAnchor: ReaderPositionAnchor) -> Bool {
        guard let pendingViewItemsSnapshot else { return false }
        self.pendingViewItemsSnapshot = nil
        return applyViewItemsSnapshot(
          pendingViewItemsSnapshot,
          preferredAnchor: preferredAnchor
        )
      }

      func resolvedItem(for anchor: ReaderPositionAnchor) -> ReaderViewItem? {
        viewItemsSnapshot.resolvedItem(for: anchor)
      }

      func spreadIndex(for item: ReaderViewItem) -> Int? {
        viewItemsSnapshot.index(for: item)
      }

      func beginTransition() -> Int {
        preloadTask?.cancel()
        preloadTask = nil
        transitionToken += 1
        isTransitioning = true
        return transitionToken
      }

      private func clearProgrammaticTransition() {
        programmaticTransitionToken = nil
        programmaticTargetItem = nil
        transitionWatchdogTask?.cancel()
        transitionWatchdogTask = nil
      }

      // UIKit can drop the completion/delegate callbacks of a programmatic
      // page-curl turn (observed on iPadOS 17 in dual-page mode). Recover
      // through the normal finish path instead of leaving the reader frozen
      // with isTransitioning stuck.
      private func scheduleProgrammaticTransitionWatchdog(
        token: Int,
        targetItem: ReaderViewItem,
        targetAnchor: ReaderPositionAnchor,
        explicitTarget: ReaderPositionAnchor?,
        direction: UIPageViewController.NavigationDirection,
        on pageViewController: UIPageViewController
      ) {
        transitionWatchdogTask?.cancel()
        transitionWatchdogTask = Task { @MainActor [weak self, weak pageViewController] in
          try? await Task.sleep(for: .seconds(1.5))
          guard !Task.isCancelled,
            let self,
            let pageViewController,
            self.isActive,
            self.pageViewController === pageViewController,
            self.isTransitioning,
            self.transitionToken == token,
            self.programmaticTransitionToken == token
          else { return }
          self.finishProgrammaticTransition(
            token: token,
            completed: true,
            targetItem: targetItem,
            targetAnchor: targetAnchor,
            consumedNavigationTarget: explicitTarget,
            pageViewController: pageViewController,
            direction: direction
          )
        }
      }

      func processNavigationTarget(
        on pageViewController: UIPageViewController,
        restoreModelPosition: Bool = false
      ) {
        guard isActive, self.pageViewController === pageViewController, !isTransitioning,
          !isPanGestureActive
        else {
          return
        }

        let explicitTarget = parent.viewModel.navigationTarget
        let target: (anchor: ReaderPositionAnchor, item: ReaderViewItem)?
        if let explicitTarget,
          let item = viewItemsSnapshot.matchingItem(for: explicitTarget)
        {
          target = (explicitTarget, item)
        } else if explicitTarget == nil, restoreModelPosition {
          let modelAnchor = parent.viewModel.captureCurrentPositionAnchor()
          target = resolvedItem(for: modelAnchor).map { (modelAnchor, $0) }
        } else {
          target = nil
        }

        guard let target, let targetSpreadIndex = spreadIndex(for: target.item) else {
          if let explicitTarget {
            let modelSnapshot = PageCurlViewItemsSnapshot(items: parent.viewModel.viewItems)
            if viewItemsSnapshot == modelSnapshot {
              retriedNavigationTarget = nil
              scheduleNavigationContinuation(
                consuming: explicitTarget,
                on: pageViewController
              )
            }
          }
          return
        }
        let currentSpreadIndex = currentResolvedSpreadIndex() ?? targetSpreadIndex

        guard targetSpreadIndex != currentSpreadIndex else {
          currentItem = target.item
          if let explicitTarget {
            retriedNavigationTarget = nil
            // Clear before committing: the commit publishes observable position
            // writes that re-enter updateUIViewController inside the same
            // SwiftUI flush, and a still-set navigationTarget would loop this
            // path forever (the deferred clearing continuation never runs on
            // the blocked main actor).
            parent.viewModel.clearNavigationTarget(matching: explicitTarget)
            commitCurrentItem(target.item, preserving: explicitTarget)
            scheduleNavigationContinuation(
              consuming: nil,
              on: pageViewController
            )
          }
          return
        }

        guard let targetPair = pageControllerPair(for: targetSpreadIndex) else {
          if let explicitTarget {
            retriedNavigationTarget = nil
            scheduleNavigationContinuation(
              consuming: explicitTarget,
              on: pageViewController
            )
          }
          return
        }

        let direction: UIPageViewController.NavigationDirection
        if parent.mode.isRTL {
          direction = targetSpreadIndex > currentSpreadIndex ? .reverse : .forward
        } else {
          direction = targetSpreadIndex > currentSpreadIndex ? .forward : .reverse
        }

        let token = beginTransition()
        programmaticTransitionToken = token
        programmaticTargetItem = target.item
        scheduleProgrammaticTransitionWatchdog(
          token: token,
          targetItem: target.item,
          targetAnchor: target.anchor,
          explicitTarget: explicitTarget,
          direction: direction,
          on: pageViewController
        )
        let shouldAnimateTransition = hasCompletedInitialUpdate && parent.animateTapTurns
        PageCurlControllerPlanner.safeSetViewControllers(
          targetPair,
          on: pageViewController,
          direction: direction,
          animated: shouldAnimateTransition
        ) { [weak self, weak pageViewController] completed in
          guard let self, let pageViewController else { return }
          self.finishProgrammaticTransition(
            token: token,
            completed: completed || !shouldAnimateTransition,
            targetItem: target.item,
            targetAnchor: target.anchor,
            consumedNavigationTarget: explicitTarget,
            pageViewController: pageViewController,
            direction: direction
          )
        }
      }

      func finishProgrammaticTransition(
        token: Int,
        completed: Bool,
        targetItem: ReaderViewItem,
        targetAnchor: ReaderPositionAnchor,
        consumedNavigationTarget: ReaderPositionAnchor?,
        pageViewController: UIPageViewController,
        direction: UIPageViewController.NavigationDirection
      ) {
        guard isActive,
          token == transitionToken,
          self.pageViewController === pageViewController
        else { return }
        clearProgrammaticTransition()
        isTransitioning = false
        transitionTargetItem = nil

        if completed {
          retriedNavigationTarget = nil
          let anchor = localAnchor(for: targetItem, preserving: targetAnchor)
          let pendingAnchor: ReaderPositionAnchor
          if consumedNavigationTarget != nil,
            let pendingViewItemsSnapshot,
            pendingViewItemsSnapshot.matchingItem(for: anchor) == nil
          {
            pendingAnchor = parent.viewModel.captureCurrentPositionAnchor()
          } else {
            pendingAnchor = anchor
          }
          applyPendingViewItemsSnapshot(preferredAnchor: pendingAnchor)

          let committedItem =
            consumedNavigationTarget == nil
            ? viewItemsSnapshot.resolvedItem(for: anchor)
            : viewItemsSnapshot.matchingItem(for: anchor)
          if let committedItem,
            let committedSpreadIndex = viewItemsSnapshot.index(for: committedItem)
          {
            if let committedPair = pageControllerPair(for: committedSpreadIndex) {
              PageCurlControllerPlanner.safeSetViewControllers(
                committedPair,
                on: pageViewController,
                direction: direction,
                animated: false
              )
            }
            commitCurrentItem(committedItem, preserving: anchor)
          } else {
            refreshVisibleControllerConfiguration()
          }
          scheduleNavigationContinuation(
            consuming: consumedNavigationTarget,
            on: pageViewController
          )
        } else {
          syncCurrentItemWithVisibleController()
          let anchor = currentPositionAnchor()
          applyPendingViewItemsSnapshot(preferredAnchor: anchor)
          refreshVisibleControllerConfiguration()
          if let consumedNavigationTarget,
            retriedNavigationTarget != consumedNavigationTarget
          {
            retriedNavigationTarget = consumedNavigationTarget
            scheduleNavigationContinuation(consuming: nil, on: pageViewController)
          }
        }
      }

      func scheduleNavigationContinuation(
        consuming target: ReaderPositionAnchor?,
        on pageViewController: UIPageViewController
      ) {
        if let target {
          consumedNavigationTarget = target
        }
        guard navigationContinuationTask == nil else { return }

        navigationContinuationTask = Task { @MainActor [weak self, weak pageViewController] in
          await Task.yield()
          guard !Task.isCancelled,
            let self,
            let pageViewController,
            self.isActive,
            self.pageViewController === pageViewController
          else { return }

          let consumedTarget = self.consumedNavigationTarget
          self.consumedNavigationTarget = nil
          self.navigationContinuationTask = nil
          if let consumedTarget {
            self.parent.viewModel.clearNavigationTarget(matching: consumedTarget)
          }
          self.processNavigationTarget(on: pageViewController)
        }
      }

      private func localAnchor(
        for item: ReaderViewItem,
        preserving anchor: ReaderPositionAnchor?
      ) -> ReaderPositionAnchor {
        let focusedPageID: ReaderPageID?
        if let preferredPageID = anchor?.focusedPageID,
          item.pageIDs.contains(preferredPageID) || item.pageID == preferredPageID
        {
          focusedPageID = preferredPageID
        } else {
          focusedPageID = item.pageID
        }
        return ReaderPositionAnchor(
          item: item,
          focusedPageID: focusedPageID,
          preferredSplitPart: item.preferredSplitPart(preserving: anchor)
        )
      }

      private func currentPositionAnchor() -> ReaderPositionAnchor {
        let capturedAnchor = parent.viewModel.captureCurrentPositionAnchor()
        return ReaderPositionAnchor(
          item: currentItem,
          focusedPageID: capturedAnchor.focusedPageID,
          preferredSplitPart: currentItem?.preferredSplitPart(preserving: capturedAnchor)
        )
      }

      private func commitCurrentItem(
        _ item: ReaderViewItem,
        preserving preferredAnchor: ReaderPositionAnchor?
      ) {
        guard isActive else { return }
        currentItem = item
        let anchor = localAnchor(for: item, preserving: preferredAnchor)
        parent.viewModel.updateCurrentPosition(anchor: anchor)

        preloadTask?.cancel()
        let token = transitionToken
        let viewModel = parent.viewModel
        preloadTask = Task(priority: .utility) { @MainActor [weak self, weak viewModel] in
          guard !Task.isCancelled,
            let self,
            self.isActive,
            token == self.transitionToken,
            self.currentItem == item,
            let viewModel
          else { return }
          await viewModel.preloadPages()
        }
      }

      func teardown(pageViewController: UIPageViewController) {
        guard isActive else { return }
        isActive = false
        unregisterViewModelObservation()
        transitionToken += 1
        isTransitioning = false
        hasCompletedInitialUpdate = false
        transitionTargetItem = nil
        pendingViewItemsSnapshot = nil

        preloadTask?.cancel()
        preloadTask = nil
        navigationContinuationTask?.cancel()
        navigationContinuationTask = nil
        consumedNavigationTarget = nil
        retriedNavigationTarget = nil
        clearProgrammaticTransition()

        pageViewController.dataSource = nil
        pageViewController.delegate = nil
        for recognizer in pageViewController.gestureRecognizers {
          if recognizer is UIPanGestureRecognizer {
            recognizer.removeTarget(self, action: #selector(handlePagePanGesture(_:)))
          }
          if recognizer.delegate === self {
            recognizer.delegate = nil
          }
        }
        for recognizer in installedTapRecognizers {
          recognizer.view?.removeGestureRecognizer(recognizer)
        }
        installedTapRecognizers.removeAll()
        doubleTapRecognizer = nil
        controllerIdentities.removeAllObjects()
        currentItem = nil
        self.pageViewController = nil
      }

      fileprivate func updateViewModelObservation(_ viewModel: ReaderViewModel) {
        guard observedViewModel !== viewModel || pagePresentationObserverToken == nil else { return }
        unregisterViewModelObservation()
        observedViewModel = viewModel
        pagePresentationObserverToken = viewModel.addPagePresentationInvalidationObserver {
          [weak self] _ in
          guard let self else { return }
          self.refreshVisibleControllerConfiguration()
        }
      }

      fileprivate func unregisterViewModelObservation() {
        guard let observedViewModel, let pagePresentationObserverToken else {
          self.observedViewModel = nil
          self.pagePresentationObserverToken = nil
          return
        }
        observedViewModel.removePagePresentationInvalidationObserver(pagePresentationObserverToken)
        self.observedViewModel = nil
        self.pagePresentationObserverToken = nil
      }

      private func beforeSpreadIndex(from spreadIndex: Int) -> Int {
        parent.mode.isRTL ? spreadIndex + 1 : spreadIndex - 1
      }

      private func afterSpreadIndex(from spreadIndex: Int) -> Int {
        parent.mode.isRTL ? spreadIndex - 1 : spreadIndex + 1
      }

      private func isValidSpreadIndex(_ spreadIndex: Int) -> Bool {
        spreadIndex >= 0 && spreadIndex < totalSpreads
      }

      private func isFirstSpreadInSegment(_ spreadIndex: Int) -> Bool {
        guard spreadIndex >= 0 else { return false }
        if spreadIndex == 0 { return true }
        guard let previousItem = viewItemsSnapshot.item(at: spreadIndex - 1) else { return false }
        if case .end = previousItem {
          return true
        }
        return false
      }

      private func isLastSpreadInSegment(_ spreadIndex: Int) -> Bool {
        guard spreadIndex >= 0 else { return false }
        if spreadIndex >= totalSpreads - 1 { return true }
        guard let nextItem = viewItemsSnapshot.item(at: spreadIndex + 1) else { return false }
        if case .end = nextItem {
          return true
        }
        return false
      }

      private func coverSlot() -> SpreadSlot {
        parent.mode.isRTL ? .first : .second
      }

      private func oppositeSlot(of slot: SpreadSlot) -> SpreadSlot {
        slot == .first ? .second : .first
      }

      private func preferredSlotForSingleSpread(at spreadIndex: Int) -> SpreadSlot {
        let cover = coverSlot()
        if isFirstSpreadInSegment(spreadIndex) {
          return cover
        }
        if isLastSpreadInSegment(spreadIndex) {
          return oppositeSlot(of: cover)
        }
        return cover
      }

      private func spineAlignment(for slot: SpreadSlot) -> HorizontalAlignment {
        if parent.mode.isRTL {
          return slot == .first ? .leading : .trailing
        }
        return slot == .first ? .trailing : .leading
      }

      private func slotContent(for spreadIndex: Int, slot: SpreadSlot) -> SlotContent? {
        guard isValidSpreadIndex(spreadIndex) else { return nil }
        guard let item = viewItemsSnapshot.item(at: spreadIndex) else { return nil }

        switch item {
        case .dual(let firstID, let secondID):
          let targetPageID: ReaderPageID
          if parent.mode.isRTL {
            targetPageID = slot == .first ? secondID : firstID
          } else {
            targetPageID = slot == .first ? firstID : secondID
          }
          return .page(pageID: targetPageID, splitMode: .none)
        case .page(let id):
          guard preferredSlotForSingleSpread(at: spreadIndex) == slot else {
            return .placeholder
          }
          return .page(pageID: id, splitMode: .none)
        case .split(let id, let part):
          if part == .both {
            let firstIsLeftHalf = parent.viewModel.isLeftSplitHalf(
              part: .first,
              readingDirection: parent.readingDirection,
              splitWidePageMode: parent.splitWidePageMode
            )
            let secondIsLeftHalf = parent.viewModel.isLeftSplitHalf(
              part: .second,
              readingDirection: parent.readingDirection,
              splitWidePageMode: parent.splitWidePageMode
            )

            let slotUsesFirstLogicalPart: Bool
            if parent.mode.isRTL {
              slotUsesFirstLogicalPart = slot == .second
            } else {
              slotUsesFirstLogicalPart = slot == .first
            }

            let isLeftHalf = slotUsesFirstLogicalPart ? firstIsLeftHalf : secondIsLeftHalf
            let splitMode: PageSplitMode = isLeftHalf ? .leftHalf : .rightHalf
            return .page(pageID: id, splitMode: splitMode)
          }

          guard preferredSlotForSingleSpread(at: spreadIndex) == slot else {
            return .placeholder
          }
          let isLeftHalf = parent.viewModel.isLeftSplitHalf(
            part: part,
            readingDirection: parent.readingDirection,
            splitWidePageMode: parent.splitWidePageMode
          )
          let splitMode: PageSplitMode = isLeftHalf ? .leftHalf : .rightHalf
          return .page(pageID: id, splitMode: splitMode)
        case .end(let id):
          return .end(segmentBookId: id.bookId)
        }
      }

      private func makePlaceholderController() -> UIViewController {
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = UIColor(parent.renderConfig.readerBackground.color)
        return placeholder
      }

      private func registerIdentity(
        for controller: UIViewController,
        item: ReaderViewItem,
        role: PageCurlControllerIdentity.Role,
        slot: SpreadSlot
      ) {
        controllerIdentities.setObject(
          PageCurlControllerIdentity(item: item, role: role, slot: slot.rawValue),
          forKey: controller
        )
      }

      private func controllerMetadata(
        for controller: UIViewController
      ) -> (item: ReaderViewItem, slot: SpreadSlot, role: PageCurlControllerIdentity.Role)? {
        guard let identity = controllerIdentities.object(forKey: controller),
          let item = identity.item,
          let slotRawValue = identity.slot,
          let slot = SpreadSlot(rawValue: slotRawValue)
        else {
          return nil
        }
        return (item: item, slot: slot, role: identity.role)
      }

      private func configureImageController(
        _ controller: NativeImagePageViewController,
        pageID: ReaderPageID,
        splitMode: PageSplitMode,
        alignment: HorizontalAlignment
      ) {
        controller.configure(
          viewModel: parent.viewModel,
          pageID: pageID,
          splitMode: splitMode,
          alignment: alignment,
          readingDirection: parent.readingDirection,
          renderConfig: parent.renderConfig
        )
      }

      private func configureEndController(
        _ controller: NativeEndPageViewController,
        segmentBookId: String,
        slot: SpreadSlot
      ) {
        let sectionDisplayMode: NativeEndPageViewController.SectionDisplayMode
        if parent.mode.isRTL {
          sectionDisplayMode = slot == .first ? .nextOnly : .previousOnly
        } else {
          sectionDisplayMode = slot == .first ? .previousOnly : .nextOnly
        }
        controller.configure(
          previousBook: parent.viewModel.endPagePreviousBook(forSegmentBookId: segmentBookId),
          nextBook: parent.viewModel.nextBook(forSegmentBookId: segmentBookId),
          readListContext: parent.readListContext,
          readingDirection: parent.readingDirection,
          sectionDisplayMode: sectionDisplayMode,
          renderConfig: parent.renderConfig,
          nextBookOfflineState: parent.viewModel.nextBookOfflineState(forSegmentBookId: segmentBookId),
          remainingUnreadCount: parent.viewModel.remainingUnreadCount(forSegmentBookId: segmentBookId),
          onDismiss: parent.onDismiss
        )
      }

      private func configureController(
        _ controller: UIViewController,
        spreadIndex: Int,
        slot: SpreadSlot
      ) -> Bool {
        guard let content = slotContent(for: spreadIndex, slot: slot) else { return false }

        switch content {
        case .page(let pageID, let splitMode):
          guard let imageController = controller as? NativeImagePageViewController else { return false }
          configureImageController(
            imageController,
            pageID: pageID,
            splitMode: splitMode,
            alignment: spineAlignment(for: slot)
          )
          return true
        case .end(let segmentBookId):
          guard let endController = controller as? NativeEndPageViewController else { return false }
          configureEndController(endController, segmentBookId: segmentBookId, slot: slot)
          return true
        case .placeholder:
          guard !(controller is NativeImagePageViewController),
            !(controller is NativeEndPageViewController)
          else { return false }
          controller.view.backgroundColor = UIColor(parent.renderConfig.readerBackground.color)
          return true
        }
      }

      private func pageController(for spreadIndex: Int, slot: SpreadSlot) -> UIViewController? {
        guard !viewItemsSnapshot.isEmpty else { return nil }
        guard let item = viewItemsSnapshot.item(at: spreadIndex) else { return nil }
        guard let content = slotContent(for: spreadIndex, slot: slot) else { return nil }

        let controller: UIViewController
        let role: PageCurlControllerIdentity.Role
        switch content {
        case .page(let pageID, let splitMode):
          let imageController = NativeImagePageViewController()
          configureImageController(
            imageController,
            pageID: pageID,
            splitMode: splitMode,
            alignment: spineAlignment(for: slot)
          )
          controller = imageController
          role = .content
        case .end(let segmentBookId):
          let endController = NativeEndPageViewController()
          configureEndController(endController, segmentBookId: segmentBookId, slot: slot)
          controller = endController
          role = .content
        case .placeholder:
          controller = makePlaceholderController()
          role = .placeholder
        }

        registerIdentity(for: controller, item: item, role: role, slot: slot)
        return controller
      }

      func pageControllerPair(for spreadIndex: Int) -> [UIViewController]? {
        guard let first = pageController(for: spreadIndex, slot: .first),
          let second = pageController(for: spreadIndex, slot: .second)
        else {
          return nil
        }
        return [first, second]
      }

      private func spreadItems(
        from controllers: [UIViewController]
      ) -> [ReaderViewItem] {
        var seenItems: Set<ReaderViewItem> = []
        return controllers.compactMap { controller in
          guard let item = controllerMetadata(for: controller)?.item,
            seenItems.insert(item).inserted
          else { return nil }
          return item
        }
      }

      private func exactSpreadIndex(for item: ReaderViewItem?) -> Int? {
        guard let item else { return nil }
        return viewItemsSnapshot.index(for: item)
      }

      func currentResolvedSpreadIndex() -> Int? {
        guard let currentItem else { return nil }
        let capturedAnchor = parent.viewModel.captureCurrentPositionAnchor()
        return viewItemsSnapshot.index(
          for: ReaderPositionAnchor(
            item: currentItem,
            focusedPageID: capturedAnchor.focusedPageID,
            preferredSplitPart: currentItem.preferredSplitPart(preserving: capturedAnchor)
          )
        )
      }

      private func resolvedVisibleSpreadIndex() -> Int? {
        guard let visibleControllers = pageViewController?.viewControllers else { return nil }
        let uniqueItems = spreadItems(from: visibleControllers)
        guard !uniqueItems.isEmpty else { return nil }
        if uniqueItems.count == 1 {
          return exactSpreadIndex(for: uniqueItems[0])
        }
        if let transitionTargetSpreadIndex = exactSpreadIndex(for: transitionTargetItem),
          uniqueItems.contains(where: { exactSpreadIndex(for: $0) == transitionTargetSpreadIndex })
        {
          return transitionTargetSpreadIndex
        }
        if let currentSpreadIndex = currentResolvedSpreadIndex(),
          uniqueItems.contains(where: { exactSpreadIndex(for: $0) == currentSpreadIndex })
        {
          return currentSpreadIndex
        }
        return uniqueItems.compactMap { exactSpreadIndex(for: $0) }.first
      }

      func syncCurrentItemWithVisibleController() {
        if let visibleSpreadIndex = resolvedVisibleSpreadIndex() {
          currentItem = viewItemsSnapshot.item(at: visibleSpreadIndex)
        }
      }

      func refreshVisibleControllerConfiguration() {
        guard !isTransitioning, !isPanGestureActive else { return }
        guard let pageViewController else { return }
        guard let visibleControllers = pageViewController.viewControllers else { return }
        guard let spreadIndex = resolvedVisibleSpreadIndex() ?? currentResolvedSpreadIndex() else { return }

        var needsReplacement = false
        for controller in visibleControllers {
          guard let metadata = controllerMetadata(for: controller) else {
            needsReplacement = true
            break
          }
          guard let expectedItem = viewItemsSnapshot.item(at: spreadIndex),
            metadata.item == expectedItem
          else {
            needsReplacement = true
            break
          }
          if !configureController(controller, spreadIndex: spreadIndex, slot: metadata.slot) {
            needsReplacement = true
            break
          }
        }

        if needsReplacement, let replacementPair = pageControllerPair(for: spreadIndex) {
          PageCurlControllerPlanner.safeSetViewControllers(
            replacementPair,
            on: pageViewController,
            direction: .forward,
            animated: false
          )
        }
      }

      // MARK: - UIPageViewControllerDataSource

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        guard let metadata = controllerMetadata(for: viewController),
          let spreadIndex = viewItemsSnapshot.index(for: metadata.item)
        else { return nil }

        switch metadata.slot {
        case .first:
          let targetSpreadIndex = beforeSpreadIndex(from: spreadIndex)
          guard isValidSpreadIndex(targetSpreadIndex) else { return nil }
          return pageController(for: targetSpreadIndex, slot: .second)
        case .second:
          guard isValidSpreadIndex(spreadIndex) else { return nil }
          return pageController(for: spreadIndex, slot: .first)
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        guard let metadata = controllerMetadata(for: viewController),
          let spreadIndex = viewItemsSnapshot.index(for: metadata.item)
        else { return nil }

        switch metadata.slot {
        case .first:
          guard isValidSpreadIndex(spreadIndex) else { return nil }
          return pageController(for: spreadIndex, slot: .second)
        case .second:
          let targetSpreadIndex = afterSpreadIndex(from: spreadIndex)
          guard isValidSpreadIndex(targetSpreadIndex) else { return nil }
          return pageController(for: targetSpreadIndex, slot: .first)
        }
      }

      // MARK: - UIPageViewControllerDelegate

      func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        guard isActive, self.pageViewController === pageViewController else { return }
        let pendingItems = spreadItems(from: pendingViewControllers)
        let pendingTarget =
          pendingItems.first(where: { $0 != currentItem }) ?? pendingItems.first
        // UIKit also fires willTransitionTo for programmatic turns. Bumping the
        // token there would orphan the in-flight completion handler, so only
        // gesture-driven turns supersede the current transition.
        if let programmaticTargetItem, pendingItems.contains(programmaticTargetItem) {
          transitionTargetItem = pendingTarget
          return
        }
        clearProgrammaticTransition()
        _ = beginTransition()
        transitionTargetItem = pendingTarget
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
      ) {
        guard isActive, self.pageViewController === pageViewController else { return }
        clearProgrammaticTransition()
        isTransitioning = false
        syncCurrentItemWithVisibleController()

        guard completed else {
          transitionTargetItem = nil
          let anchor = currentPositionAnchor()
          applyPendingViewItemsSnapshot(preferredAnchor: anchor)
          refreshVisibleControllerConfiguration()
          scheduleNavigationContinuation(consuming: nil, on: pageViewController)
          return
        }

        let committedCandidate = transitionTargetItem ?? currentItem
        transitionTargetItem = nil
        guard let committedCandidate else {
          let anchor = parent.viewModel.captureCurrentPositionAnchor()
          applyPendingViewItemsSnapshot(preferredAnchor: anchor)
          refreshVisibleControllerConfiguration()
          scheduleNavigationContinuation(consuming: nil, on: pageViewController)
          return
        }

        let anchor = localAnchor(
          for: committedCandidate,
          preserving: currentPositionAnchor()
        )
        applyPendingViewItemsSnapshot(preferredAnchor: anchor)
        let committedItem =
          viewItemsSnapshot.matchingItem(for: anchor)
          ?? viewItemsSnapshot.resolvedItem(
            for: parent.viewModel.captureCurrentPositionAnchor()
          )
        guard let committedItem,
          let committedSpreadIndex = viewItemsSnapshot.index(for: committedItem),
          isValidSpreadIndex(committedSpreadIndex)
        else {
          refreshVisibleControllerConfiguration()
          scheduleNavigationContinuation(consuming: nil, on: pageViewController)
          return
        }

        if let committedPair = pageControllerPair(for: committedSpreadIndex) {
          PageCurlControllerPlanner.safeSetViewControllers(
            committedPair,
            on: pageViewController,
            direction: .forward,
            animated: false
          )
        }

        commitCurrentItem(committedItem, preserving: anchor)
        scheduleNavigationContinuation(consuming: nil, on: pageViewController)
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
      ) -> UIPageViewController.SpineLocation {
        .mid
      }

      @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let view = gesture.view else { return }
        guard !isTapZoneSuppressed else { return }

        let location = gesture.location(in: view)
        dispatchTapZoneTap(at: location, in: view)
      }

      @objc private func handleDoubleTap(_: UITapGestureRecognizer) {}

      @objc private func handleLongPress(_: UILongPressGestureRecognizer) {}

      @objc fileprivate func handlePagePanGesture(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
        guard !isTransitioning, !isPanGestureActive, let pageViewController else { return }
        let anchor = currentPositionAnchor()
        applyPendingViewItemsSnapshot(preferredAnchor: anchor)
        refreshVisibleControllerConfiguration()
        scheduleNavigationContinuation(consuming: nil, on: pageViewController)
      }

      private var isTapZoneSuppressed: Bool {
        isTransitioning
          || parent.viewModel.isZoomed
      }

      private func dispatchTapZoneTap(at location: CGPoint, in view: UIView) {
        guard !isTapZoneSuppressed else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        parent.onTapZoneTap(
          min(max(location.x / bounds.width, 0), 1),
          min(max(location.y / bounds.height, 0), 1)
        )
      }

      // MARK: - UIGestureRecognizerDelegate

      private func primaryTranslation(for pan: UIPanGestureRecognizer) -> CGFloat {
        pan.translation(in: pan.view).x
      }

      private func primaryVelocity(for pan: UIPanGestureRecognizer) -> CGFloat {
        pan.velocity(in: pan.view).x
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isTransitioning else { return false }
        guard !parent.viewModel.isZoomed else { return false }

        syncCurrentItemWithVisibleController()
        guard let currentSpreadIndex = currentResolvedSpreadIndex(),
          isValidSpreadIndex(currentSpreadIndex)
        else { return false }

        let beforeExists = isValidSpreadIndex(beforeSpreadIndex(from: currentSpreadIndex))
        let afterExists = isValidSpreadIndex(afterSpreadIndex(from: currentSpreadIndex))

        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
          let primaryTranslation = primaryTranslation(for: pan)
          let primaryVelocity = primaryVelocity(for: pan)

          let directionTranslationThreshold: CGFloat = 1
          let directionVelocityThreshold: CGFloat = 60

          let directionSignal: CGFloat
          if abs(primaryTranslation) >= directionTranslationThreshold {
            directionSignal = primaryTranslation
          } else if abs(primaryVelocity) >= directionVelocityThreshold {
            directionSignal = primaryVelocity
          } else {
            directionSignal = 0
          }

          if directionSignal > 0 {
            return beforeExists
          }

          if directionSignal < 0 {
            return afterExists
          }

          return beforeExists && afterExists
        }

        return true
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view?.hasInteractiveAncestor != true
      }
    }
  }
#endif
