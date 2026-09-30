#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  struct NativeCoverPageView: UIViewRepresentable {
    private struct SlotRenderState {
      let isVisible: Bool
      let isMoving: Bool
      let isElevated: Bool
      let isActive: Bool
      let zIndex: Double

      static let hidden = SlotRenderState(
        isVisible: false,
        isMoving: false,
        isElevated: false,
        isActive: false,
        zIndex: -1
      )
    }

    private enum TransitionMetrics {
      static let minimumDragDistance: CGFloat = 1
      static let directionalDragBias: CGFloat = 4
      static let overscrollResistance: CGFloat = 0.2
      static let cancelThreshold: CGFloat = 0.5
      static let commitDistanceRatio: CGFloat = 0.18
      static let commitVelocityThreshold: CGFloat = 700
      static let gestureAnimationDuration: Double = 0.3
      static let movingShadowOpacity: Double = 0.12
      static let idleShadowOpacity: Double = 0.05
      static let movingShadowRadius: CGFloat = 5
      static let idleShadowRadius: CGFloat = 2
      static let movingShadowOffset: CGFloat = 3
      static let idleShadowOffset: CGFloat = 1
    }

    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let tapNavigationAnimationDuration: Double
    let renderConfig: ReaderRenderConfig
    @Bindable var viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIView(context: Context) -> NativeCoverContainerView {
      let containerView = NativeCoverContainerView()
      containerView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleContainerLayout()
      }
      context.coordinator.attach(to: containerView)
      context.coordinator.update(from: self)
      return containerView
    }

    func updateUIView(_ uiView: NativeCoverContainerView, context: Context) {
      context.coordinator.attach(to: uiView)
      context.coordinator.update(from: self)
    }

    static func dismantleUIView(_ uiView: NativeCoverContainerView, coordinator: Coordinator) {
      coordinator.teardown()
      uiView.prepareForDismantle()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, NativePagedPagePresentationHost {
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
      private var panRecognizer: UIPanGestureRecognizer?
      private var singleTapRecognizer: UITapGestureRecognizer?
      private var doubleTapRecognizer: UITapGestureRecognizer?
      private var longPressRecognizer: UILongPressGestureRecognizer?

      init(_ parent: NativeCoverPageView) {
        self.parent = parent
        super.init()
        pagePresentationCoordinator.host = self
      }

      func attach(to containerView: NativeCoverContainerView) {
        self.containerView = containerView
        containerView.backgroundColor = UIColor(parent.renderConfig.readerBackground.color)
        attachPanRecognizerIfNeeded(to: containerView)
        attachTapRecognizersIfNeeded(to: containerView)
      }

      func update(from parent: NativeCoverPageView) {
        self.parent = parent
        pagePresentationCoordinator.update(viewModel: parent.viewModel)
        containerView?.backgroundColor = UIColor(parent.renderConfig.readerBackground.color)
        applyPanRecognizerState()
        applyDoubleTapRecognizerState()

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
        if let singleTapRecognizer {
          singleTapRecognizer.view?.removeGestureRecognizer(singleTapRecognizer)
        }
        if let doubleTapRecognizer {
          doubleTapRecognizer.view?.removeGestureRecognizer(doubleTapRecognizer)
        }
        if let longPressRecognizer {
          longPressRecognizer.view?.removeGestureRecognizer(longPressRecognizer)
        }
        panRecognizer = nil
        singleTapRecognizer = nil
        doubleTapRecognizer = nil
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
          // A viewport change (rotation) distorts the pan recognizer's
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

      @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let containerView else { return }
        switch recognizer.state {
        case .changed:
          handlePanChanged(translation: recognizer.translation(in: containerView))
        case .ended:
          handlePanEnded(
            translation: recognizer.translation(in: containerView),
            velocity: recognizer.velocity(in: containerView)
          )
        case .cancelled, .failed:
          resetDragStateImmediately()
        default:
          break
        }
      }

      private func attachPanRecognizerIfNeeded(to containerView: NativeCoverContainerView) {
        #if os(iOS) || os(macOS)
          if panRecognizer?.view === containerView {
            return
          }

          if let panRecognizer {
            panRecognizer.view?.removeGestureRecognizer(panRecognizer)
          }

          let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
          panRecognizer.maximumNumberOfTouches = 1
          panRecognizer.cancelsTouchesInView = false
          panRecognizer.delegate = self
          containerView.addGestureRecognizer(panRecognizer)
          self.panRecognizer = panRecognizer
          applyPanRecognizerState()
        #endif
      }

      private func attachTapRecognizersIfNeeded(to containerView: NativeCoverContainerView) {
        if singleTapRecognizer?.view === containerView,
          doubleTapRecognizer?.view === containerView,
          longPressRecognizer?.view === containerView
        {
          return
        }

        if let singleTapRecognizer {
          singleTapRecognizer.view?.removeGestureRecognizer(singleTapRecognizer)
        }
        if let doubleTapRecognizer {
          doubleTapRecognizer.view?.removeGestureRecognizer(doubleTapRecognizer)
        }
        if let longPressRecognizer {
          longPressRecognizer.view?.removeGestureRecognizer(longPressRecognizer)
        }

        let singleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTapRecognizer.numberOfTapsRequired = 1
        singleTapRecognizer.cancelsTouchesInView = false
        singleTapRecognizer.delegate = self
        containerView.addGestureRecognizer(singleTapRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        doubleTapRecognizer.delegate = self
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        containerView.addGestureRecognizer(doubleTapRecognizer)

        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.delegate = self
        singleTapRecognizer.require(toFail: longPressRecognizer)
        containerView.addGestureRecognizer(longPressRecognizer)

        self.singleTapRecognizer = singleTapRecognizer
        self.doubleTapRecognizer = doubleTapRecognizer
        self.longPressRecognizer = longPressRecognizer
        applyDoubleTapRecognizerState()
      }

      private func applyPanRecognizerState() {
        #if os(iOS) || os(macOS)
          guard let panRecognizer else { return }
          let wasEnabled = panRecognizer.isEnabled
          let shouldEnable = !parent.viewModel.isZoomed && !isAnimatingTransition
          guard wasEnabled != shouldEnable else { return }
          let previousState = panRecognizer.state
          panRecognizer.isEnabled = shouldEnable
          if wasEnabled && !shouldEnable && (previousState == .began || previousState == .changed) {
            resetDragStateImmediately()
          }
        #endif
      }

      private func applyDoubleTapRecognizerState() {
        doubleTapRecognizer?.isEnabled = parent.renderConfig.doubleTapZoomMode.isEnabled
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
          alignCurrentWholeSpread(with: targetAnchor, animated: tapNavigationTransitionDuration > 0)
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

      private func handlePanChanged(translation: CGPoint) {
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

      private func handlePanEnded(translation: CGPoint, velocity: CGPoint) {
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
          // The item list was rebuilt underneath an in-flight transition (e.g. an
          // orientation flip changed single/dual layout). A stale target can still
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
          if abs(dragOffset) < TransitionMetrics.cancelThreshold {
            dragOffset = backwardStartOffset(for: directionSign)
            updateSlotLayout()
          }
          animateDragOffset(to: 0, duration: duration, token: token) {
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
        // A freshly committed page is never zoomed. Clear any stale scale left on
        // a slot that was zoomed while the transition animation was in flight
        // (the animation allows user interaction), then reconcile the shared zoom
        // flag so the tap zones, controls, and pan recognizer re-enable.
        containerView?.slotViews.forEach { $0.forceResetZoom() }
        parent.viewModel.isZoomed = false
        if navigationTarget != nil, let positionAnchor {
          alignCurrentWholeSpread(with: positionAnchor, animated: tapNavigationTransitionDuration > 0)
        }
      }

      /// Pans the current whole spread to the edge an explicit navigation
      /// target names, e.g. a step toward its far edge.
      private func alignCurrentWholeSpread(with anchor: ReaderPositionAnchor, animated: Bool) {
        guard let edge = ReaderSpreadEdge(splitPart: anchor.preferredSplitPart),
          let containerView
        else { return }
        containerView.slotViews[deckState.frontSlotIndex].panWholeSpread(to: edge, animated: animated)
      }

      private func wholeSpreadPresentation(for item: ReaderViewItem?) -> WholeSpreadPresentation? {
        guard let item else { return nil }
        return parent.viewModel.wholeSpreadPresentation(
          for: item,
          isDualPagePresentation: parent.mode.isDualPage,
          readingDirection: parent.readingDirection,
          splitWidePageMode: parent.splitWidePageMode,
          relativeTo: deckState.currentItem
        )
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

      private func animateDragOffset(
        to targetOffset: CGFloat,
        duration: Double,
        token: Int,
        completion: @escaping () -> Void
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

        UIView.animate(
          withDuration: duration,
          delay: 0,
          options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
          self.dragOffset = targetOffset
          self.updateSlotLayout()
          containerView.layoutIfNeeded()
        } completion: { _ in
          guard token == self.transitionToken else { return }
          completion()
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
          let item = deckState.item(at: slotIndex)
          slotView.configure(
            item: item,
            wholeSpread: wholeSpreadPresentation(for: item),
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
          slotView.isUserInteractionEnabled = renderState.isVisible && renderState.isActive
        }
      }

      private func updateSlotLayout() {
        guard let containerView else { return }

        for (slotIndex, slotView) in containerView.slotViews.enumerated() {
          let renderState = slotRenderState(for: slotIndex)
          let offset = renderState.isMoving ? dragOffset : 0
          let shadow = pageShadow(for: offset, isElevated: renderState.isElevated)

          slotView.frame = shiftedFrame(for: containerView.bounds, offset: offset)
          slotView.isHidden = !renderState.isVisible || slotView.item == nil
          slotView.alpha = renderState.isVisible ? 1 : 0
          slotView.layer.zPosition = CGFloat(renderState.zIndex)
          slotView.layer.masksToBounds = false
          slotView.layer.shadowColor = UIColor.black.cgColor
          slotView.layer.shadowOpacity = Float(shadow.opacity)
          slotView.layer.shadowRadius = shadow.radius
          slotView.layer.shadowOffset = CGSize(width: shadow.x, height: shadow.y)
          slotView.layer.shadowPath = UIBezierPath(rect: slotView.bounds).cgPath
          slotView.isUserInteractionEnabled = renderState.isVisible && renderState.isActive
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

      private func primaryTranslation(from point: CGPoint) -> CGFloat {
        parent.mode.isVertical ? point.y : point.x
      }

      private func secondaryTranslation(from point: CGPoint) -> CGFloat {
        parent.mode.isVertical ? point.x : point.y
      }

      private func primaryVelocity(from point: CGPoint) -> CGFloat {
        parent.mode.isVertical ? point.y : point.x
      }

      private func isPrimaryDirectionalDrag(_ point: CGPoint) -> Bool {
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

      @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard let containerView else { return }
        guard !isTapZoneSuppressed else { return }

        let location = recognizer.location(in: containerView)
        dispatchTapZoneTap(at: location, in: containerView)
      }

      @objc private func handleDoubleTap(_: UITapGestureRecognizer) {}

      @objc private func handleLongPress(_: UILongPressGestureRecognizer) {}

      private var isTapZoneSuppressed: Bool {
        parent.viewModel.isZoomed
          || isUserPanning
          || isAnimatingTransition
      }

      private func dispatchTapZoneTap(at location: CGPoint, in containerView: NativeCoverContainerView) {
        guard !isTapZoneSuppressed else { return }
        let bounds = containerView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        parent.onTapZoneTap(
          min(max(location.x / bounds.width, 0), 1),
          min(max(location.y / bounds.height, 0), 1)
        )
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        guard !parent.viewModel.isZoomed else { return false }
        guard !isAnimatingTransition else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let velocity = pan.velocity(in: containerView)
        // A whole spread pans before the page turns: drags it can still follow
        // belong to its scroll view.
        if let containerView,
          let dragX = pan.horizontalDrag(in: containerView),
          containerView.slotViews[deckState.frontSlotIndex].canPanWholeSpread(forHorizontalDrag: dragX)
        {
          return false
        }
        if velocity == .zero {
          return true
        }
        return isPrimaryDirectionalDrag(velocity)
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
      ) -> Bool {
        touch.view?.hasInteractiveAncestor != true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        gestureRecognizer === longPressRecognizer || otherGestureRecognizer === longPressRecognizer
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        guard gestureRecognizer === panRecognizer else { return false }
        let typeName = String(describing: type(of: otherGestureRecognizer))
        return typeName.contains("Parallax")
          || typeName.contains("ZoomTransition")
          || typeName.contains("ScreenEdgePan")
          || typeName.contains("FullPageSwipe")
          || typeName == "_UIContentSwipeDismissGestureRecognizer"
      }
    }
  }
#endif
