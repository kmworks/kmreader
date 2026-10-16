#if os(macOS)
  import AppKit
  import SwiftUI

  extension NativeCoverPageView {
    @MainActor
    final class Coordinator: NSObject, NSGestureRecognizerDelegate, NativePagedPagePresentationHost {
      private enum TransitionAnimationKind {
        case gesture
        case tapNavigation
      }

      private var parent: NativeCoverPageView
      private weak var containerView: NativeCoverContainerView?
      private let pagePresentationCoordinator = NativePagedPagePresentationCoordinator()

      private var deckState = NativeCoverDeckState()
      private var transitionDirection: Int?
      private var dragOffset: CGFloat = 0
      private var isAnimatingTransition = false
      private var transitionToken = 0
      private var lastViewportSize: CGSize = .zero
      private var postTransitionTask: Task<Void, Never>?
      private var panRecognizer: NSPanGestureRecognizer?
      private var clickRecognizer: NSClickGestureRecognizer?
      private var doubleClickRecognizer: NSClickGestureRecognizer?
      private var longPressRecognizer: NSPressGestureRecognizer?
      private var singleClickWorkItem: DispatchWorkItem?

      init(_ parent: NativeCoverPageView) {
        self.parent = parent
        super.init()
        pagePresentationCoordinator.host = self
      }

      func attach(to containerView: NativeCoverContainerView) {
        self.containerView = containerView
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(parent.renderConfig.readerBackground.color).cgColor
        attachPanRecognizerIfNeeded(to: containerView)
        attachClickRecognizersIfNeeded(to: containerView)
      }

      func update(from parent: NativeCoverPageView) {
        self.parent = parent
        pagePresentationCoordinator.update(viewModel: parent.viewModel)
        containerView?.layer?.backgroundColor = NSColor(parent.renderConfig.readerBackground.color).cgColor
        applyPanRecognizerState()

        if deckState.currentItem == nil {
          syncCurrentItemFromViewModel(force: true)
        } else if !isAnimatingTransition {
          syncCurrentItemFromViewModel()
          if let navigationTarget = parent.viewModel.navigationTarget {
            // While the user is actively panning, discard tap-initiated navigation.
            // `isAnimatingTransition` only covers the post-pan commit/cancel animation;
            // during the pan itself it is false, so an unguarded tap would call
            // `commitTransition` mid-drag and override the user's gesture.
            if isUserPanning {
              clearNavigationTargetIfMatching(navigationTarget)
            } else {
              handleNavigationTarget(navigationTarget)
            }
          } else {
            syncSlotContent()
            updateSlotLayout()
          }
        }

        pagePresentationCoordinator.flushIfPossible()
      }

      func teardown() {
        // Invalidate any in-flight transition so a pending animation completion
        // cannot commit into the shared view model after the rebuild.
        transitionToken += 1
        transitionDirection = nil
        isAnimatingTransition = false
        postTransitionTask?.cancel()
        postTransitionTask = nil
        if let panRecognizer {
          panRecognizer.view?.removeGestureRecognizer(panRecognizer)
        }
        if let clickRecognizer {
          clickRecognizer.view?.removeGestureRecognizer(clickRecognizer)
        }
        if let doubleClickRecognizer {
          doubleClickRecognizer.view?.removeGestureRecognizer(doubleClickRecognizer)
        }
        if let longPressRecognizer {
          longPressRecognizer.view?.removeGestureRecognizer(longPressRecognizer)
        }
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
        panRecognizer = nil
        clickRecognizer = nil
        doubleClickRecognizer = nil
        longPressRecognizer = nil
        pagePresentationCoordinator.teardown()
        containerView = nil
      }

      func handleContainerLayout() {
        guard let containerView else { return }
        let newSize = containerView.bounds.size
        guard newSize != .zero else { return }
        let sizeChanged = newSize != lastViewportSize
        lastViewportSize = newSize
        if sizeChanged && isUserPanning {
          // A viewport change (window resize) distorts the pan recognizer's
          // translation; cancel an in-flight drag instead of letting it commit
          // against a coordinate space that no longer applies.
          resetDragStateImmediately()
        }
        if sizeChanged && !isAnimatingTransition {
          syncSlotContent()
        }
        updateSlotLayout()
        pagePresentationCoordinator.flushIfPossible()
      }

      func hasVisiblePagePresentationContent() -> Bool {
        guard let containerView else { return false }
        return containerView.slotViews.contains(where: { !$0.isHidden && $0.item != nil })
      }

      func applyPagePresentationInvalidation(_ invalidation: ReaderPagePresentationInvalidation) {
        guard let containerView else { return }

        switch invalidation {
        case .all:
          containerView.slotViews.forEach { slotView in
            guard !slotView.isHidden else { return }
            slotView.refreshContent()
          }
        case .pages(let pageIDs):
          containerView.slotViews.forEach { slotView in
            guard !slotView.isHidden else { return }
            guard slotView.containsAny(pageIDs: pageIDs) else { return }
            slotView.refreshContent()
          }
        }
      }

      @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard let containerView else { return }
        let translation = recognizer.translation(in: containerView)
        switch recognizer.state {
        case .changed:
          handlePanChanged(translation: translation)
        case .ended:
          handlePanEnded(translation: translation, velocity: recognizer.velocity(in: containerView))
        case .cancelled, .failed:
          resetDragStateImmediately()
        default:
          break
        }
      }

      private func attachPanRecognizerIfNeeded(to containerView: NativeCoverContainerView) {
        if panRecognizer?.view === containerView {
          return
        }

        if let panRecognizer {
          panRecognizer.view?.removeGestureRecognizer(panRecognizer)
        }

        let panRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panRecognizer.delegate = self
        containerView.addGestureRecognizer(panRecognizer)
        self.panRecognizer = panRecognizer
        applyPanRecognizerState()
      }

      private func attachClickRecognizersIfNeeded(to containerView: NativeCoverContainerView) {
        if clickRecognizer?.view === containerView,
          doubleClickRecognizer?.view === containerView,
          longPressRecognizer?.view === containerView
        {
          return
        }

        if let clickRecognizer {
          clickRecognizer.view?.removeGestureRecognizer(clickRecognizer)
        }
        if let doubleClickRecognizer {
          doubleClickRecognizer.view?.removeGestureRecognizer(doubleClickRecognizer)
        }
        if let longPressRecognizer {
          longPressRecognizer.view?.removeGestureRecognizer(longPressRecognizer)
        }

        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        clickRecognizer.numberOfClicksRequired = 1
        clickRecognizer.delegate = self
        containerView.addGestureRecognizer(clickRecognizer)

        let doubleClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClickRecognizer.numberOfClicksRequired = 2
        doubleClickRecognizer.delegate = self
        containerView.addGestureRecognizer(doubleClickRecognizer)

        let longPressRecognizer = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.delegate = self
        containerView.addGestureRecognizer(longPressRecognizer)

        self.clickRecognizer = clickRecognizer
        self.doubleClickRecognizer = doubleClickRecognizer
        self.longPressRecognizer = longPressRecognizer
      }

      private func applyPanRecognizerState() {
        guard let panRecognizer else { return }
        let wasEnabled = panRecognizer.isEnabled
        let shouldEnable = !parent.viewModel.isZoomed && !isAnimatingTransition
        guard wasEnabled != shouldEnable else { return }
        let previousState = panRecognizer.state
        panRecognizer.isEnabled = shouldEnable
        if wasEnabled && !shouldEnable && (previousState == .began || previousState == .changed) {
          resetDragStateImmediately()
        }
      }

      private var currentItem: ReaderViewItem? {
        deckState.currentItem
      }

      private var isUserPanning: Bool {
        guard let panRecognizer else { return false }
        switch panRecognizer.state {
        case .began, .changed:
          return true
        default:
          return false
        }
      }

      private var pendingTargetItem: ReaderViewItem? {
        guard let transitionDirection else { return nil }
        return transitionDirection == 1 ? deckState.nextItem : deckState.previousItem
      }

      private var tapNavigationTransitionDuration: Double {
        max(parent.tapNavigationAnimationDuration, 0)
      }

      private var gestureTransitionDuration: Double {
        TransitionMetrics.gestureAnimationDuration
      }

      private var primaryExtent: CGFloat {
        guard let containerView else { return 1 }
        let size = containerView.bounds.size
        return max(parent.mode.isVertical ? size.height : size.width, 1)
      }

      private var isCurrentItemValid: Bool {
        guard let currentItem else { return false }
        return parent.viewModel.viewItemIndex(for: currentItem) != nil
      }

      private func syncCurrentItemFromViewModel(force: Bool = false) {
        let resolved = parent.viewModel.currentViewItem() ?? parent.viewModel.viewItems.first
        if !force,
          let resolved,
          let currentItem,
          resolved == currentItem,
          isCurrentItemValid,
          transitionDirection == nil
        {
          deckState.updateAdjacentSlots(around: resolved, viewModel: parent.viewModel)
          syncSlotContent()
          updateSlotLayout()
          return
        }

        if let resolved, let currentItem, resolved == currentItem {
          deckState.updateAdjacentSlots(around: resolved, viewModel: parent.viewModel)
          transitionDirection = nil
          dragOffset = 0
          syncSlotContent()
          updateSlotLayout()
          if force {
            applyCurrentItem(resolved)
          }
          return
        }

        guard let resolved else {
          deckState.reset()
          transitionDirection = nil
          dragOffset = 0
          syncSlotContent()
          updateSlotLayout()
          postTransitionTask?.cancel()
          postTransitionTask = nil
          return
        }

        deckState.rebuild(around: resolved, viewModel: parent.viewModel)
        transitionDirection = nil
        dragOffset = 0
        syncSlotContent()
        updateSlotLayout()
        applyCurrentItem(resolved)
      }

      private func resolveNavigationTarget(_ target: ReaderPositionAnchor) -> ReaderPositionAnchor? {
        parent.viewModel.matchingPositionAnchor(for: target)
      }

      private func clearNavigationTargetIfMatching(_ target: ReaderPositionAnchor) {
        parent.viewModel.clearNavigationTarget(matching: target)
      }

      private func handleNavigationTarget(_ target: ReaderPositionAnchor) {
        guard let targetAnchor = resolveNavigationTarget(target),
          let targetItem = targetAnchor.item
        else {
          clearNavigationTargetIfMatching(target)
          return
        }

        guard let currentItem else {
          deckState.rebuild(around: targetItem, viewModel: parent.viewModel)
          syncSlotContent()
          updateSlotLayout()
          applyCurrentPosition(targetAnchor)
          clearNavigationTargetIfMatching(target)
          return
        }

        guard let currentIndex = parent.viewModel.viewItemIndex(for: currentItem),
          let targetIndex = parent.viewModel.viewItemIndex(for: targetItem)
        else {
          clearNavigationTargetIfMatching(target)
          return
        }

        guard targetIndex != currentIndex else {
          applyCurrentPosition(targetAnchor)
          clearNavigationTargetIfMatching(target)
          return
        }

        if abs(targetIndex - currentIndex) == 1 {
          dragOffset = 0
          commitTransition(
            to: targetItem,
            positionAnchor: targetAnchor,
            navigationTarget: target,
            animation: .tapNavigation
          )
        } else {
          deckState.rebuild(around: targetItem, viewModel: parent.viewModel)
          transitionDirection = nil
          dragOffset = 0
          syncSlotContent()
          updateSlotLayout()
          applyCurrentPosition(targetAnchor)
          clearNavigationTargetIfMatching(target)
        }
      }

      private func handlePanChanged(translation: NSPoint) {
        guard !parent.viewModel.isZoomed else { return }
        guard !isAnimatingTransition else { return }
        guard let currentItem else { return }
        guard isPrimaryDirectionalDrag(translation) else { return }

        let primary = primaryTranslation(from: translation)
        guard abs(primary) > TransitionMetrics.minimumDragDistance else { return }

        let directionOffset = adjacentOffset(for: primary)
        guard let targetItem = parent.viewModel.adjacentViewItem(from: currentItem, offset: directionOffset) else {
          dragOffset = primary * TransitionMetrics.overscrollResistance
          transitionDirection = nil
          updateSlotLayout()
          return
        }

        transitionDirection = directionOffset
        deckState.prepareTransitionTarget(targetItem, direction: directionOffset)
        syncSlotContent()
        if directionOffset == 1 {
          dragOffset = primary
        } else {
          dragOffset = backwardInteractiveOffset(for: primary)
        }
        updateSlotLayout()
      }

      private func handlePanEnded(translation: NSPoint, velocity: NSPoint) {
        guard !parent.viewModel.isZoomed else {
          resetDragStateImmediately()
          return
        }
        guard !isAnimatingTransition else { return }
        guard isPrimaryDirectionalDrag(translation) else {
          resetDragStateImmediately()
          return
        }

        guard pendingTargetItem != nil else {
          if abs(dragOffset) > TransitionMetrics.cancelThreshold {
            cancelDragWithAnimation()
          } else {
            resetDragStateImmediately()
          }
          return
        }

        let primary = primaryTranslation(from: translation)
        let primaryVelocity = primaryVelocity(from: velocity)
        let shouldCommit =
          abs(primary) > primaryExtent * TransitionMetrics.commitDistanceRatio
          || abs(primaryVelocity) > TransitionMetrics.commitVelocityThreshold

        if shouldCommit {
          commitCurrentDrag()
        } else {
          cancelDragWithAnimation()
        }
      }

      private func commitCurrentDrag() {
        guard let targetItem = pendingTargetItem else {
          cancelDragWithAnimation()
          return
        }
        commitTransition(to: targetItem, animation: .gesture)
      }

      private func commitTransition(
        to targetItem: ReaderViewItem,
        positionAnchor: ReaderPositionAnchor? = nil,
        navigationTarget: ReaderPositionAnchor? = nil,
        animation: TransitionAnimationKind
      ) {
        guard let currentItem,
          let currentIndex = parent.viewModel.viewItemIndex(for: currentItem),
          let targetIndex = parent.viewModel.viewItemIndex(for: targetItem)
        else {
          // The item list was rebuilt underneath an in-flight transition (e.g. a
          // window resize flipped single/dual layout). A stale target can still
          // match an `.end` item by identity and skip the reader to the volume
          // transition, so discard the transition and re-sync from the committed
          // position instead of completing it.
          if let navigationTarget {
            clearNavigationTargetIfMatching(navigationTarget)
          }
          resetDragStateImmediately()
          syncCurrentItemFromViewModel(force: true)
          return
        }

        let direction = targetIndex > currentIndex ? 1 : -1
        transitionDirection = direction
        deckState.prepareTransitionTarget(targetItem, direction: direction)
        syncSlotContent()

        let directionSign = transitionDirectionSign(from: currentIndex, to: targetIndex)
        let endOffset = directionSign * primaryExtent

        isAnimatingTransition = true
        transitionToken += 1
        let token = transitionToken
        let duration = transitionDuration(for: animation)

        if targetIndex > currentIndex {
          animateDragOffset(to: endOffset, duration: duration, token: token) {
            self.completeTransition(
              to: targetItem,
              positionAnchor: positionAnchor,
              navigationTarget: navigationTarget
            )
          }
        } else {
          animateBackwardCommitWithPreparedStartStateIfNeeded(
            directionSign: directionSign,
            duration: duration,
            token: token
          ) {
            self.completeTransition(
              to: targetItem,
              positionAnchor: positionAnchor,
              navigationTarget: navigationTarget
            )
          }
        }
      }

      private func completeTransition(
        to targetItem: ReaderViewItem,
        positionAnchor: ReaderPositionAnchor?,
        navigationTarget: ReaderPositionAnchor?
      ) {
        let direction = transitionDirection ?? 1
        deckState.rotateAfterCommit(
          to: targetItem,
          direction: direction,
          viewModel: parent.viewModel
        )
        transitionDirection = nil
        dragOffset = 0
        isAnimatingTransition = false
        syncSlotContent()
        updateSlotLayout()
        if let positionAnchor {
          applyCurrentPosition(positionAnchor)
        } else {
          applyCurrentItem(targetItem)
        }
        if let navigationTarget {
          clearNavigationTargetIfMatching(navigationTarget)
        }
        applyPanRecognizerState()
      }

      private func cancelDragWithAnimation() {
        transitionToken += 1
        let token = transitionToken
        let cancelTargetOffset: CGFloat = {
          guard transitionDirection == -1,
            let currentItem,
            let pendingTargetItem,
            let currentIndex = parent.viewModel.viewItemIndex(for: currentItem),
            let targetIndex = parent.viewModel.viewItemIndex(for: pendingTargetItem)
          else {
            return 0
          }
          let directionSign = transitionDirectionSign(from: currentIndex, to: targetIndex)
          return backwardStartOffset(for: directionSign)
        }()

        isAnimatingTransition = true
        animateDragOffset(to: cancelTargetOffset, duration: gestureTransitionDuration, token: token) {
          self.resetDragStateImmediately()
        }
      }

      private func resetDragStateImmediately() {
        transitionDirection = nil
        dragOffset = 0
        isAnimatingTransition = false
        syncSlotContent()
        updateSlotLayout()
        applyPanRecognizerState()
      }

      private func animateBackwardCommitWithPreparedStartStateIfNeeded(
        directionSign: CGFloat,
        duration: Double,
        token: Int,
        completion: @escaping @MainActor () -> Void
      ) {
        guard abs(dragOffset) < TransitionMetrics.cancelThreshold else {
          animateDragOffset(to: 0, duration: duration, token: token, completion: completion)
          return
        }

        dragOffset = backwardStartOffset(for: directionSign)
        updateSlotLayout()
        containerView?.layoutSubtreeIfNeeded()
        containerView?.displayIfNeeded()
        containerView?.window?.displayIfNeeded()

        Task { @MainActor in
          await Task.yield()
          guard token == self.transitionToken else { return }
          self.animateDragOffset(to: 0, duration: duration, token: token, completion: completion)
        }
      }

      private func animateDragOffset(
        to targetOffset: CGFloat,
        duration: Double,
        token: Int,
        completion: @escaping @MainActor () -> Void
      ) {
        guard let containerView else {
          dragOffset = targetOffset
          completion()
          return
        }

        if duration <= 0 {
          dragOffset = targetOffset
          updateSlotLayout()
          guard token == transitionToken else { return }
          completion()
          return
        }

        NSAnimationContext.runAnimationGroup { context in
          context.duration = duration
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          self.dragOffset = targetOffset
          self.updateSlotLayout(animated: true)
          containerView.layoutSubtreeIfNeeded()
        } completionHandler: {
          Task { @MainActor in
            guard token == self.transitionToken else { return }
            completion()
          }
        }
      }

      private func transitionDuration(for animation: TransitionAnimationKind) -> Double {
        switch animation {
        case .gesture:
          gestureTransitionDuration
        case .tapNavigation:
          tapNavigationTransitionDuration
        }
      }

      private func applyCurrentItem(_ item: ReaderViewItem) {
        let currentAnchor = parent.viewModel.captureCurrentPositionAnchor()
        let focusedPageID = currentAnchor.item == item ? currentAnchor.focusedPageID : item.pageID
        applyCurrentPosition(
          ReaderPositionAnchor(
            item: item,
            focusedPageID: focusedPageID,
            preferredSplitPart: item.preferredSplitPart(preserving: currentAnchor)
          )
        )
      }

      private func applyCurrentPosition(_ anchor: ReaderPositionAnchor) {
        guard let item = anchor.item else { return }
        postTransitionTask?.cancel()
        let token = transitionToken
        parent.viewModel.updateCurrentPosition(anchor: anchor)

        postTransitionTask = Task(priority: .utility) {
          guard !Task.isCancelled else { return }

          let shouldContinue = await MainActor.run { () -> Bool in
            guard token == self.transitionToken else { return false }
            guard self.currentItem == item else { return false }
            return true
          }
          guard shouldContinue else { return }

          await preloadPresentationWindow(around: item)
          await parent.viewModel.preloadPages()
        }
      }

      private func preloadPresentationWindow(around item: ReaderViewItem) async {
        let candidateItems = [
          item,
          parent.viewModel.adjacentViewItem(from: item, offset: 1),
          parent.viewModel.adjacentViewItem(from: item, offset: -1),
        ].compactMap { $0 }

        var pageIDs: [ReaderPageID] = []
        var seenPageIDs: Set<ReaderPageID> = []
        for candidateItem in candidateItems {
          for pageID in candidateItem.pageIDs where seenPageIDs.insert(pageID).inserted {
            pageIDs.append(pageID)
          }
        }

        guard !pageIDs.isEmpty else { return }

        parent.viewModel.prioritizeVisiblePageLoads(for: item.pageIDs)

        for pageID in pageIDs {
          guard !Task.isCancelled else { return }
          _ = await parent.viewModel.preloadImage(for: pageID)
        }
      }

      private func syncSlotContent() {
        guard let containerView else { return }
        let viewportSize = containerView.bounds.size
        for (slotIndex, slotView) in containerView.slotViews.enumerated() {
          let renderState = slotRenderState(for: slotIndex)
          slotView.configure(
            item: deckState.item(at: slotIndex),
            viewModel: parent.viewModel,
            screenSize: viewportSize,
            readingDirection: parent.readingDirection,
            splitWidePageMode: parent.splitWidePageMode,
            renderConfig: parent.renderConfig,
            readListContext: parent.readListContext,
            isVisible: renderState.isVisible,
            isPlaybackActive: renderState.isActive,
            tracksGlobalZoomState: renderState.isActive,
            onDismiss: parent.onDismiss
          )
        }
      }

      private func updateSlotLayout(animated: Bool = false) {
        guard let containerView else { return }

        for (slotIndex, slotView) in containerView.slotViews.enumerated() {
          let renderState = slotRenderState(for: slotIndex)
          let offset = renderState.isMoving ? dragOffset : 0
          let shadow = pageShadow(for: offset, isElevated: renderState.isElevated)
          let frame = shiftedFrame(for: containerView.bounds, offset: offset)

          slotView.wantsLayer = true
          if animated {
            slotView.animator().frame = frame
            slotView.animator().alphaValue = renderState.isVisible ? 1 : 0
          } else {
            slotView.frame = frame
            slotView.alphaValue = renderState.isVisible ? 1 : 0
          }
          slotView.isHidden = !renderState.isVisible || slotView.item == nil
          slotView.layer?.zPosition = renderState.zIndex
          slotView.layer?.masksToBounds = false
          slotView.layer?.shadowColor = NSColor.black.cgColor
          slotView.layer?.shadowOpacity = Float(shadow.opacity)
          slotView.layer?.shadowRadius = shadow.radius
          slotView.layer?.shadowOffset = CGSize(width: shadow.x, height: shadow.y)
          slotView.layer?.shadowPath = CGPath(rect: slotView.bounds, transform: nil)
        }
      }

      private func shiftedFrame(for bounds: CGRect, offset: CGFloat) -> CGRect {
        var frame = bounds
        if parent.mode.isVertical {
          frame.origin.y += offset
        } else {
          frame.origin.x += offset
        }
        return frame
      }

      private func slotRenderState(for slotIndex: Int) -> SlotRenderState {
        if let transitionDirection {
          if transitionDirection == 1 {
            if slotIndex == deckState.frontSlotIndex {
              return SlotRenderState(isVisible: true, isMoving: true, isElevated: true, isActive: true, zIndex: 1)
            }
            if slotIndex == deckState.middleSlotIndex {
              return SlotRenderState(
                isVisible: true,
                isMoving: false,
                isElevated: false,
                isActive: false,
                zIndex: 0
              )
            }
            return .hidden
          }

          if slotIndex == deckState.backSlotIndex {
            return SlotRenderState(isVisible: true, isMoving: true, isElevated: true, isActive: false, zIndex: 1)
          }
          if slotIndex == deckState.frontSlotIndex {
            return SlotRenderState(
              isVisible: true,
              isMoving: false,
              isElevated: false,
              isActive: true,
              zIndex: 0
            )
          }
          return .hidden
        }

        if slotIndex == deckState.frontSlotIndex {
          return SlotRenderState(isVisible: true, isMoving: false, isElevated: true, isActive: true, zIndex: 1)
        }
        return .hidden
      }

      private func pageShadow(for offset: CGFloat, isElevated: Bool) -> (
        opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat
      ) {
        guard isElevated else {
          return (0, 0, 0, 0)
        }

        let isMoving = abs(offset) > TransitionMetrics.cancelThreshold
        let opacity: Double = isMoving ? TransitionMetrics.movingShadowOpacity : TransitionMetrics.idleShadowOpacity
        let radius: CGFloat = isMoving ? TransitionMetrics.movingShadowRadius : TransitionMetrics.idleShadowRadius

        if parent.mode.isVertical {
          let y: CGFloat =
            isMoving
            ? (offset < 0 ? TransitionMetrics.movingShadowOffset : -TransitionMetrics.movingShadowOffset)
            : TransitionMetrics.idleShadowOffset
          return (opacity, radius, 0, y)
        }

        let x: CGFloat =
          isMoving
          ? (offset < 0 ? TransitionMetrics.movingShadowOffset : -TransitionMetrics.movingShadowOffset)
          : 0
        return (opacity, radius, x, TransitionMetrics.idleShadowOffset)
      }

      private func primaryTranslation(from point: NSPoint) -> CGFloat {
        parent.mode.isVertical ? point.y : point.x
      }

      private func secondaryTranslation(from point: NSPoint) -> CGFloat {
        parent.mode.isVertical ? point.x : point.y
      }

      private func primaryVelocity(from point: NSPoint) -> CGFloat {
        parent.mode.isVertical ? point.y : point.x
      }

      private func isPrimaryDirectionalDrag(_ point: NSPoint) -> Bool {
        abs(primaryTranslation(from: point))
          > abs(secondaryTranslation(from: point)) + TransitionMetrics.directionalDragBias
      }

      private func adjacentOffset(for translation: CGFloat) -> Int {
        if parent.mode.isVertical {
          return translation < 0 ? 1 : -1
        }
        if parent.mode.isRTL {
          return translation > 0 ? 1 : -1
        }
        return translation < 0 ? 1 : -1
      }

      private func transitionDirectionSign(from currentIndex: Int, to targetIndex: Int) -> CGFloat {
        let isForward = targetIndex > currentIndex
        if parent.mode.isVertical {
          return isForward ? -1 : 1
        }
        if parent.mode.isRTL {
          return isForward ? 1 : -1
        }
        return isForward ? -1 : 1
      }

      private func backwardStartOffset(for directionSign: CGFloat) -> CGFloat {
        -directionSign * primaryExtent
      }

      private func backwardInteractiveOffset(for translation: CGFloat) -> CGFloat {
        let translationSign: CGFloat = translation >= 0 ? 1 : -1
        let start = backwardStartOffset(for: translationSign)
        let raw = start + translation
        if start < 0 {
          return min(max(raw, start), 0)
        }
        return max(min(raw, start), 0)
      }

      @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        singleClickWorkItem?.cancel()
        guard recognizer.state == .ended else { return }
        guard let containerView else { return }
        guard !isTapZoneSuppressed else { return }

        let location = recognizer.location(in: containerView)
        guard !isInteractiveElement(at: location, in: containerView) else { return }
        let workItem = DispatchWorkItem { [weak self, weak containerView] in
          guard let self, let containerView else { return }
          self.dispatchTapZoneTap(at: location, in: containerView)
        }
        singleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
      }

      @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
      }

      @objc private func handleLongPress(_: NSPressGestureRecognizer) {}

      private var isTapZoneSuppressed: Bool {
        parent.viewModel.isZoomed
          || isUserPanning
          || isAnimatingTransition
      }

      private func dispatchTapZoneTap(at location: CGPoint, in containerView: NativeCoverContainerView) {
        singleClickWorkItem = nil
        guard !isTapZoneSuppressed else { return }
        let bounds = containerView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        parent.onTapZoneTap(
          min(max(location.x / bounds.width, 0), 1),
          min(max(1 - (location.y / bounds.height), 0), 1)
        )
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer {
          return !parent.viewModel.isZoomed && !isAnimatingTransition
        }
        // Clicks/presses landing on interactive elements (e.g. the end card's
        // Close button) must reach the control, not the tap-zone recognizers.
        if gestureRecognizer === clickRecognizer || gestureRecognizer === doubleClickRecognizer
          || gestureRecognizer === longPressRecognizer,
          let containerView,
          isInteractiveElement(at: gestureRecognizer.location(in: containerView), in: containerView)
        {
          return false
        }
        return !isTapZoneSuppressed
      }

      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
      ) -> Bool {
        gestureRecognizer === clickRecognizer && otherGestureRecognizer === longPressRecognizer
      }

      private func isInteractiveElement(at location: CGPoint, in containerView: NativeCoverContainerView) -> Bool {
        containerView.hitTest(location)?.hasInteractiveAncestor == true
      }
    }
  }
#endif
