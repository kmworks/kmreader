//
// CurlPageView.swift
//

#if os(iOS)
  import Foundation
  import SwiftUI
  import UIKit

  struct CurlPageView: UIViewControllerRepresentable {
    @Bindable var viewModel: ReaderViewModel
    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let animateTapTurns: Bool
    let renderConfig: ReaderRenderConfig
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
      let spineLocation: UIPageViewController.SpineLocation = mode.isRTL ? .max : .min
      let pageViewController = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: mode.isVertical ? .vertical : .horizontal,
        options: [.spineLocation: NSNumber(value: spineLocation.rawValue)]
      )

      context.coordinator.attach(to: pageViewController)
      context.coordinator.installTapRecognizers(on: pageViewController.view)

      for recognizer in pageViewController.gestureRecognizers {
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
        pageViewController: pageViewController,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageViewController)
      context.coordinator.installInitialControllers(on: pageViewController)

      return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
      context.coordinator.update(parent: self, pageViewController: pageViewController)
    }

    static func dismantleUIViewController(
      _ pageViewController: UIPageViewController,
      coordinator: Coordinator
    ) {
      coordinator.teardown(from: pageViewController)
    }

    private func pageCurlBacksideStyle() -> PageCurlBacksideViewController.Style {
      PageCurlBacksideViewController.Style(
        baseColor: UIColor(renderConfig.readerBackground.color)
      )
    }

    private func pageCurlBacksideMirrorAxis() -> PageCurlBacksideViewController.MirrorAxis {
      mode.isVertical ? .vertical : .horizontal
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
      UIGestureRecognizerDelegate
    {
      private var parent: CurlPageView
      private weak var pageViewController: UIPageViewController?
      private var isActive = false
      private var isTransitioning = false
      private var hasCompletedInitialUpdate = false
      private var currentAnchor: ReaderPositionAnchor?
      private var renderedSnapshot = PageCurlViewItemsSnapshot(items: [])
      private var pendingSnapshot: PageCurlViewItemsSnapshot?
      private var preloadTask: Task<Void, Never>?
      private var navigationContinuationTask: Task<Void, Never>?
      private var consumedNavigationTarget: ReaderPositionAnchor?
      private var retriedNavigationTarget: ReaderPositionAnchor?
      private let controllerIdentities =
        NSMapTable<UIViewController, PageCurlControllerIdentity>.weakToStrongObjects()
      private weak var singleTapRecognizer: UITapGestureRecognizer?
      private weak var doubleTapRecognizer: UITapGestureRecognizer?
      private weak var longPressRecognizer: UILongPressGestureRecognizer?
      private weak var observedViewModel: ReaderViewModel?
      private var pagePresentationObserverToken: UUID?

      init(_ parent: CurlPageView) {
        self.parent = parent
        super.init()
      }

      func attach(to pageViewController: UIPageViewController) {
        self.pageViewController = pageViewController
        isActive = true
        pageViewController.dataSource = self
        pageViewController.delegate = self
      }

      // UIKit fires willTransitionTo only once a curl actually starts, so a
      // programmatic setViewControllers landing during the pan's
      // pre-transition window corrupts the gesture and crashes the next
      // _handlePanGesture validation. Treat an active pan like a transition.
      private var isPanGestureActive: Bool {
        pageViewController?.gestureRecognizers.contains { recognizer in
          guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
          return pan.state == .began || pan.state == .changed
        } ?? false
      }

      func installInitialControllers(on pageViewController: UIPageViewController) {
        guard isCurrentAttachment(pageViewController) else { return }

        renderedSnapshot = PageCurlViewItemsSnapshot(items: parent.viewModel.viewItems)
        let modelAnchor = parent.viewModel.captureCurrentPositionAnchor()
        guard let item = renderedSnapshot.resolvedItem(for: modelAnchor) else {
          currentAnchor = nil
          installPlaceholderControllers(on: pageViewController)
          return
        }

        currentAnchor = localAnchor(for: item, preserving: modelAnchor)
        installContentControllers(
          for: item,
          on: pageViewController,
          direction: .forward,
          animated: false
        )
      }

      func update(parent: CurlPageView, pageViewController: UIPageViewController) {
        self.parent = parent
        updateViewModelObservation(parent.viewModel)
        if !isCurrentAttachment(pageViewController) {
          attach(to: pageViewController)
        }

        guard isCurrentAttachment(pageViewController) else { return }
        defer { hasCompletedInitialUpdate = true }

        applyDoubleTapRecognizerState()
        PageCurlControllerPlanner.configure(
          pageViewController: pageViewController,
          semanticContentAttribute: parent.mode.isRTL ? .forceRightToLeft : .forceLeftToRight
        )
        PageCurlBacksideViewController.applyStyle(
          parent.pageCurlBacksideStyle(),
          to: pageViewController
        )

        if !isTransitioning {
          synchronizeCurrentAnchorWithVisibleController()
        }

        let newSnapshot = PageCurlViewItemsSnapshot(items: parent.viewModel.viewItems)
        var didInstallSnapshot = false
        if isTransitioning || isPanGestureActive {
          pendingSnapshot = newSnapshot == renderedSnapshot ? nil : newSnapshot
        } else if newSnapshot != renderedSnapshot {
          applySnapshot(
            newSnapshot,
            preserving: currentAnchor ?? parent.viewModel.captureCurrentPositionAnchor(),
            on: pageViewController
          )
          didInstallSnapshot = true
        }

        guard !isTransitioning, !isPanGestureActive else { return }
        if !didInstallSnapshot {
          refreshVisibleControllerConfiguration()
        }
        processNavigationTarget(on: pageViewController)
      }

      func teardown(from pageViewController: UIPageViewController) {
        guard self.pageViewController === pageViewController else { return }

        unregisterViewModelObservation()
        isActive = false
        preloadTask?.cancel()
        preloadTask = nil
        navigationContinuationTask?.cancel()
        navigationContinuationTask = nil
        consumedNavigationTarget = nil
        retriedNavigationTarget = nil

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

        let ownedRecognizers: [UIGestureRecognizer?] = [
          singleTapRecognizer,
          doubleTapRecognizer,
          longPressRecognizer,
        ]
        for recognizer in ownedRecognizers.compactMap({ $0 }) {
          recognizer.view?.removeGestureRecognizer(recognizer)
        }
        singleTapRecognizer = nil
        doubleTapRecognizer = nil
        longPressRecognizer = nil

        controllerIdentities.removeAllObjects()
        renderedSnapshot = PageCurlViewItemsSnapshot(items: [])
        pendingSnapshot = nil
        currentAnchor = nil
        isTransitioning = false
        hasCompletedInitialUpdate = false
        self.pageViewController = nil
      }

      func installTapRecognizers(on view: UIView) {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = self
        view.addGestureRecognizer(singleTap)
        singleTapRecognizer = singleTap

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
        longPressRecognizer = longPress
        applyDoubleTapRecognizerState()
      }

      private func applyDoubleTapRecognizerState() {
        doubleTapRecognizer?.isEnabled = parent.renderConfig.doubleTapZoomMode.isEnabled
      }

      private func isCurrentAttachment(_ pageViewController: UIPageViewController) -> Bool {
        isActive && self.pageViewController === pageViewController
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

      private func applySnapshot(
        _ snapshot: PageCurlViewItemsSnapshot,
        preserving anchor: ReaderPositionAnchor,
        on pageViewController: UIPageViewController
      ) {
        guard isCurrentAttachment(pageViewController) else { return }

        renderedSnapshot = snapshot
        pendingSnapshot = nil
        guard let item = snapshot.resolvedItem(for: anchor) else {
          currentAnchor = nil
          installPlaceholderControllers(on: pageViewController)
          return
        }

        currentAnchor = localAnchor(for: item, preserving: anchor)
        installContentControllers(
          for: item,
          on: pageViewController,
          direction: .forward,
          animated: false
        )
      }

      private func applyPendingSnapshotIfNeeded(
        preserving anchor: ReaderPositionAnchor? = nil,
        on pageViewController: UIPageViewController
      ) {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != renderedSnapshot else { return }

        applySnapshot(
          pendingSnapshot,
          preserving: anchor ?? currentAnchor ?? parent.viewModel.captureCurrentPositionAnchor(),
          on: pageViewController
        )
      }

      private func registerIdentity(
        _ role: PageCurlControllerIdentity.Role,
        item: ReaderViewItem?,
        for controller: UIViewController
      ) {
        controllerIdentities.setObject(
          PageCurlControllerIdentity(item: item, role: role),
          forKey: controller
        )
      }

      private func identity(for controller: UIViewController) -> PageCurlControllerIdentity? {
        controllerIdentities.object(forKey: controller)
      }

      private func visibleItem() -> ReaderViewItem? {
        guard let visibleController = pageViewController?.viewControllers?.first else { return nil }
        return identity(for: visibleController)?.item
      }

      private func synchronizeCurrentAnchorWithVisibleController() {
        guard let item = visibleItem() else { return }
        currentAnchor = localAnchor(for: item, preserving: currentAnchor)
      }

      private func currentResolvedIndex() -> Int? {
        guard let currentAnchor else { return nil }
        return renderedSnapshot.index(for: currentAnchor)
      }

      private func configureImageController(
        _ controller: NativeImagePageViewController,
        with item: ReaderViewItem
      ) {
        let splitMode: PageSplitMode
        let pageID = item.pageID
        let wholeSpread = parent.viewModel.wholeSpreadPresentation(
          for: item,
          isDualPagePresentation: false,
          readingDirection: parent.readingDirection,
          splitWidePageMode: parent.splitWidePageMode,
          relativeTo: currentAnchor?.item
        )

        switch item {
        case .page, .dual:
          splitMode = .none
        case .split(_, let part):
          if wholeSpread != nil {
            splitMode = .none
          } else {
            let isLeftHalf = parent.viewModel.isLeftSplitHalf(
              part: part,
              readingDirection: parent.readingDirection,
              splitWidePageMode: parent.splitWidePageMode
            )
            splitMode = isLeftHalf ? .leftHalf : .rightHalf
          }
        case .end:
          return
        }

        controller.configure(
          viewModel: parent.viewModel,
          pageID: pageID,
          splitMode: splitMode,
          wholeSpread: wholeSpread,
          readingDirection: parent.readingDirection,
          renderConfig: parent.renderConfig
        )
      }

      private var visibleImageController: NativeImagePageViewController? {
        pageViewController?.viewControllers?.first as? NativeImagePageViewController
      }

      /// Pans the visible whole spread to the edge an explicit navigation
      /// target names, e.g. a step toward its far edge.
      private func alignVisibleWholeSpread(with target: ReaderPositionAnchor) {
        guard let edge = ReaderSpreadEdge(splitPart: target.preferredSplitPart) else { return }
        visibleImageController?.panWholeSpread(to: edge, animated: parent.animateTapTurns)
      }

      /// Whether the visible whole spread can still follow `pan`, which then
      /// pans the spread instead of curling the page.
      private func visibleWholeSpreadClaims(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let visibleImageController else { return false }
        let translation = pan.translation(in: pan.view)
        let drag = translation == .zero ? pan.velocity(in: pan.view) : translation
        return abs(drag.x) > abs(drag.y)
          && visibleImageController.canPanWholeSpread(forHorizontalDrag: drag.x)
      }

      private func configureEndController(
        _ controller: NativeEndPageViewController,
        segmentBookId: String
      ) {
        controller.configure(
          previousBook: parent.viewModel.endPagePreviousBook(forSegmentBookId: segmentBookId),
          nextBook: parent.viewModel.nextBook(forSegmentBookId: segmentBookId),
          readListContext: parent.readListContext,
          readingDirection: parent.readingDirection,
          renderConfig: parent.renderConfig,
          nextBookOfflineState: parent.viewModel.nextBookOfflineState(forSegmentBookId: segmentBookId),
          onDismiss: parent.onDismiss
        )
      }

      private func makeContentController(for item: ReaderViewItem) -> UIViewController {
        let controller: UIViewController
        switch item {
        case .end(let id):
          let endController = NativeEndPageViewController()
          configureEndController(endController, segmentBookId: id.bookId)
          controller = endController
        case .page, .dual, .split:
          let imageController = NativeImagePageViewController()
          configureImageController(imageController, with: item)
          controller = imageController
        }
        registerIdentity(.content, item: item, for: controller)
        return controller
      }

      private func makeBacksideController(
        for item: ReaderViewItem,
        mirroredSnapshot: PageCurlBacksideViewController.MirroredSnapshot? = nil
      ) -> PageCurlBacksideViewController {
        let controller = PageCurlBacksideViewController(
          destinationToken: item.pageID.description,
          style: parent.pageCurlBacksideStyle(),
          mirroredSnapshot: mirroredSnapshot
        )
        registerIdentity(.backside, item: item, for: controller)
        return controller
      }

      private func pageCurlControllers(
        primary: UIViewController,
        item: ReaderViewItem,
        animated: Bool,
        in pageViewController: UIPageViewController
      ) -> [UIViewController] {
        PageCurlControllerPlanner.controllers(
          primary: primary,
          animated: animated,
          in: pageViewController,
          makeBackside: {
            let mirroredSnapshot = PageCurlBacksideViewController.makeMirroredSnapshot(
              from: primary,
              axis: self.parent.pageCurlBacksideMirrorAxis()
            )
            return self.makeBacksideController(
              for: item,
              mirroredSnapshot: mirroredSnapshot
            )
          }
        )
      }

      private func installContentControllers(
        for item: ReaderViewItem,
        primary: UIViewController? = nil,
        on pageViewController: UIPageViewController,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool
      ) {
        let primaryController = primary ?? makeContentController(for: item)
        let controllers = pageCurlControllers(
          primary: primaryController,
          item: item,
          animated: animated,
          in: pageViewController
        )
        PageCurlControllerPlanner.safeSetViewControllers(
          controllers,
          on: pageViewController,
          direction: direction,
          animated: animated
        )
      }

      private func installPlaceholderControllers(on pageViewController: UIPageViewController) {
        let controllers = PageCurlControllerPlanner.placeholderControllers(
          in: pageViewController,
          backgroundColor: UIColor(parent.renderConfig.readerBackground.color)
        )
        for controller in controllers {
          registerIdentity(.placeholder, item: nil, for: controller)
        }
        PageCurlControllerPlanner.safeSetViewControllers(
          controllers,
          on: pageViewController,
          direction: .forward,
          animated: false
        )
      }

      private func updateViewModelObservation(_ viewModel: ReaderViewModel) {
        guard observedViewModel !== viewModel || pagePresentationObserverToken == nil else { return }
        unregisterViewModelObservation()
        observedViewModel = viewModel
        pagePresentationObserverToken = viewModel.addPagePresentationInvalidationObserver {
          [weak self] _ in
          guard let self else { return }
          self.refreshVisibleControllerConfiguration()
        }
      }

      private func unregisterViewModelObservation() {
        guard let observedViewModel, let pagePresentationObserverToken else {
          self.observedViewModel = nil
          self.pagePresentationObserverToken = nil
          return
        }
        observedViewModel.removePagePresentationInvalidationObserver(pagePresentationObserverToken)
        self.observedViewModel = nil
        self.pagePresentationObserverToken = nil
      }

      private func refreshVisibleControllerConfiguration() {
        guard !isTransitioning, !isPanGestureActive else { return }
        guard let pageViewController else { return }
        guard let visibleController = pageViewController.viewControllers?.first else { return }
        guard let visibleItem = identity(for: visibleController)?.item,
          let visibleIndex = renderedSnapshot.index(for: visibleItem),
          let item = renderedSnapshot.item(at: visibleIndex)
        else {
          return
        }

        switch item {
        case .end(let id):
          if let endController = visibleController as? NativeEndPageViewController {
            configureEndController(endController, segmentBookId: id.bookId)
          } else {
            installContentControllers(
              for: item,
              on: pageViewController,
              direction: .forward,
              animated: false
            )
          }
        case .page, .dual, .split:
          if let imageController = visibleController as? NativeImagePageViewController {
            configureImageController(imageController, with: item)
          } else {
            installContentControllers(
              for: item,
              on: pageViewController,
              direction: .forward,
              animated: false
            )
          }
        }
      }

      private func processNavigationTarget(on pageViewController: UIPageViewController) {
        guard isCurrentAttachment(pageViewController), !isTransitioning, !isPanGestureActive else { return }
        guard let requestedTarget = parent.viewModel.navigationTarget else { return }
        guard !renderedSnapshot.isEmpty else { return }

        guard let targetItem = renderedSnapshot.matchingItem(for: requestedTarget),
          let targetIndex = renderedSnapshot.index(for: targetItem)
        else {
          let modelSnapshot = PageCurlViewItemsSnapshot(items: parent.viewModel.viewItems)
          if renderedSnapshot == modelSnapshot {
            retriedNavigationTarget = nil
            scheduleNavigationContinuation(consuming: requestedTarget, on: pageViewController)
          }
          return
        }

        let currentIndex = currentResolvedIndex() ?? targetIndex
        guard targetIndex != currentIndex else {
          retriedNavigationTarget = nil
          // Clear before committing: the commit publishes observable position
          // writes that re-enter updateUIViewController inside the same
          // SwiftUI flush, and a still-set navigationTarget would loop this
          // path forever (the deferred clearing continuation never runs on
          // the blocked main actor).
          parent.viewModel.clearNavigationTarget(matching: requestedTarget)
          commitCurrentPosition(
            to: targetItem,
            preserving: requestedTarget
          )
          alignVisibleWholeSpread(with: requestedTarget)
          scheduleNavigationContinuation(consuming: nil, on: pageViewController)
          return
        }

        let direction: UIPageViewController.NavigationDirection
        if parent.mode.isRTL {
          direction = targetIndex > currentIndex ? .reverse : .forward
        } else {
          direction = targetIndex > currentIndex ? .forward : .reverse
        }

        let targetController = makeContentController(for: targetItem)

        let shouldAnimateTransition = hasCompletedInitialUpdate && parent.animateTapTurns
        let transitionControllers = pageCurlControllers(
          primary: targetController,
          item: targetItem,
          animated: shouldAnimateTransition,
          in: pageViewController
        )
        isTransitioning = true

        PageCurlControllerPlanner.safeSetViewControllers(
          transitionControllers,
          on: pageViewController,
          direction: direction,
          animated: shouldAnimateTransition
        ) { [weak self, weak pageViewController] completed in
          guard let self, let pageViewController else { return }
          guard self.isCurrentAttachment(pageViewController) else { return }

          self.isTransitioning = false
          if completed || !shouldAnimateTransition {
            self.retriedNavigationTarget = nil
            self.installContentControllers(
              for: targetItem,
              primary: targetController,
              on: pageViewController,
              direction: direction,
              animated: false
            )
            self.commitCurrentPosition(
              to: targetItem,
              preserving: requestedTarget
            )
            self.alignVisibleWholeSpread(with: requestedTarget)
            self.applyPendingSnapshotIfNeeded(
              preserving: self.parent.viewModel.captureCurrentPositionAnchor(),
              on: pageViewController
            )
            self.scheduleNavigationContinuation(
              consuming: requestedTarget,
              on: pageViewController
            )
          } else {
            self.synchronizeCurrentAnchorWithVisibleController()
            self.applyPendingSnapshotIfNeeded(
              preserving: self.currentAnchor,
              on: pageViewController
            )
            self.refreshVisibleControllerConfiguration()
            if self.retriedNavigationTarget != requestedTarget {
              self.retriedNavigationTarget = requestedTarget
              self.scheduleNavigationContinuation(consuming: nil, on: pageViewController)
            }
          }
        }
      }

      private func scheduleNavigationContinuation(
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
            self.isCurrentAttachment(pageViewController)
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

      private func commitCurrentPosition(
        to item: ReaderViewItem,
        preserving preferredAnchor: ReaderPositionAnchor?
      ) {
        let anchor = localAnchor(for: item, preserving: preferredAnchor)
        parent.viewModel.updateCurrentPosition(anchor: anchor)
        currentAnchor = parent.viewModel.matchingPositionAnchor(for: anchor) ?? anchor
        visibleImageController?.reportWholeSpreadPosition()

        preloadTask?.cancel()
        let viewModel = parent.viewModel
        preloadTask = Task { @MainActor [weak self] in
          await viewModel.preloadPages()
          guard !Task.isCancelled else { return }
          self?.preloadTask = nil
        }
      }

      // MARK: - UIPageViewControllerDataSource

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        guard isCurrentAttachment(pageViewController) else { return nil }
        guard let identity = identity(for: viewController), let item = identity.item else { return nil }

        switch identity.role {
        case .backside:
          guard renderedSnapshot.index(for: item) != nil else { return nil }
          return makeContentController(for: item)
        case .content:
          guard let index = renderedSnapshot.index(for: item) else { return nil }
          let targetIndex = parent.mode.isRTL ? index + 1 : index - 1
          guard let targetItem = renderedSnapshot.item(at: targetIndex) else { return nil }
          let mirroredSnapshot = mirroredSnapshotForBackside(
            targetItem: targetItem,
            currentController: viewController
          )
          return makeBacksideController(
            for: targetItem,
            mirroredSnapshot: mirroredSnapshot
          )
        case .placeholder:
          return nil
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        guard isCurrentAttachment(pageViewController) else { return nil }
        guard let identity = identity(for: viewController), let item = identity.item else { return nil }

        switch identity.role {
        case .backside:
          guard renderedSnapshot.index(for: item) != nil else { return nil }
          return makeContentController(for: item)
        case .content:
          guard let index = renderedSnapshot.index(for: item) else { return nil }
          let targetIndex = parent.mode.isRTL ? index - 1 : index + 1
          guard let targetItem = renderedSnapshot.item(at: targetIndex) else { return nil }
          let mirroredSnapshot = mirroredSnapshotForBackside(
            targetItem: targetItem,
            currentController: viewController
          )
          return makeBacksideController(
            for: targetItem,
            mirroredSnapshot: mirroredSnapshot
          )
        case .placeholder:
          return nil
        }
      }

      // MARK: - UIPageViewControllerDelegate

      func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        guard isCurrentAttachment(pageViewController) else { return }
        isTransitioning = true
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
      ) {
        guard isCurrentAttachment(pageViewController) else { return }
        isTransitioning = false

        if completed, let item = visibleItem() {
          if let visibleController = pageViewController.viewControllers?.first,
            let identity = identity(for: visibleController)
          {
            if case .backside = identity.role {
              installContentControllers(
                for: item,
                on: pageViewController,
                direction: .forward,
                animated: false
              )
            }
          }
          commitCurrentPosition(
            to: item,
            preserving: currentAnchor
          )
        } else {
          synchronizeCurrentAnchorWithVisibleController()
        }

        if !isPanGestureActive {
          applyPendingSnapshotIfNeeded(on: pageViewController)
          scheduleNavigationContinuation(consuming: nil, on: pageViewController)
        }
      }

      @objc fileprivate func handlePagePanGesture(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
        guard !isTransitioning, !isPanGestureActive, let pageViewController else { return }
        applyPendingSnapshotIfNeeded(on: pageViewController)
        refreshVisibleControllerConfiguration()
        scheduleNavigationContinuation(consuming: nil, on: pageViewController)
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
      ) -> UIPageViewController.SpineLocation {
        parent.mode.isRTL ? .max : .min
      }

      // MARK: - UIGestureRecognizerDelegate

      private func beforeIndex(from index: Int) -> Int {
        parent.mode.isRTL ? index + 1 : index - 1
      }

      private func afterIndex(from index: Int) -> Int {
        parent.mode.isRTL ? index - 1 : index + 1
      }

      private func primaryTranslation(for pan: UIPanGestureRecognizer) -> CGFloat {
        let translation = pan.translation(in: pan.view)
        return parent.mode.isVertical ? translation.y : translation.x
      }

      private func primaryVelocity(for pan: UIPanGestureRecognizer) -> CGFloat {
        let velocity = pan.velocity(in: pan.view)
        return parent.mode.isVertical ? velocity.y : velocity.x
      }

      private func mirroredSnapshotForBackside(
        targetItem: ReaderViewItem,
        currentController: UIViewController
      ) -> PageCurlBacksideViewController.MirroredSnapshot? {
        guard let currentItem = identity(for: currentController)?.item,
          let currentIndex = renderedSnapshot.index(for: currentItem),
          let targetIndex = renderedSnapshot.index(for: targetItem)
        else {
          return nil
        }

        let sourceController: UIViewController
        if targetIndex > currentIndex {
          sourceController = currentController
        } else {
          sourceController = makeContentController(for: targetItem)
        }

        return PageCurlBacksideViewController.makeMirroredSnapshot(
          from: sourceController,
          axis: parent.pageCurlBacksideMirrorAxis()
        )
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

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isTransitioning else { return false }
        guard !parent.viewModel.isZoomed else { return false }

        synchronizeCurrentAnchorWithVisibleController()
        guard let currentPageIndex = currentResolvedIndex() else { return false }

        let beforeExists = renderedSnapshot.item(at: beforeIndex(from: currentPageIndex)) != nil
        let afterExists = renderedSnapshot.item(at: afterIndex(from: currentPageIndex)) != nil

        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
          // A whole spread pans before the page turns.
          guard !visibleWholeSpreadClaims(pan) else { return false }
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

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view?.hasInteractiveAncestor != true
      }
    }
  }
#endif
