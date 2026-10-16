//
// WebPubPagedCurlView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit
  import YueduCoreText

  struct WebPubPagedCurlView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    var renderingEngine: EpubRenderingEngine = .webView
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let animateTapTurns: Bool
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
      let spineLocation = pageCurlSpineLocation
      let options: [UIPageViewController.OptionsKey: Any] = [.spineLocation: NSNumber(value: spineLocation.rawValue)]

      let pageVC = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: options
      )
      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: pageCurlSemanticContentAttribute
      )
      pageVC.dataSource = context.coordinator
      pageVC.delegate = context.coordinator
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageVC)
      context.coordinator.pageViewController = pageVC

      // Allow simultaneous gesture recognition for zoom transition return gesture
      pageVC.gestureRecognizers.forEach { recognizer in
        recognizer.delegate = context.coordinator
        if recognizer is UITapGestureRecognizer {
          recognizer.isEnabled = false
        }
        if let pan = recognizer as? UIPanGestureRecognizer {
          pan.addTarget(context.coordinator, action: #selector(Coordinator.handleInternalPanState(_:)))
        }
      }

      // Custom tap/long-press handling with TapZoneHelper
      let tapRecognizer = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleTap(_:))
      )
      tapRecognizer.cancelsTouchesInView = false
      tapRecognizer.delegate = context.coordinator
      pageVC.view.addGestureRecognizer(tapRecognizer)
      context.coordinator.tapGestureRecognizer = tapRecognizer

      let longPressRecognizer = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressRecognizer.cancelsTouchesInView = false
      longPressRecognizer.delegate = context.coordinator
      tapRecognizer.require(toFail: longPressRecognizer)
      pageVC.view.addGestureRecognizer(longPressRecognizer)
      context.coordinator.longPressGestureRecognizer = longPressRecognizer
      for case let panRecognizer as UIPanGestureRecognizer in pageVC.gestureRecognizers {
        tapRecognizer.require(toFail: panRecognizer)
      }

      context.coordinator.installInitialLocation(in: pageVC)

      return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
      context.coordinator.parent = self
      defer { context.coordinator.hasCompletedInitialUpdate = true }
      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: pageCurlSemanticContentAttribute
      )
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageVC)

      if context.coordinator.currentChapterController == nil {
        context.coordinator.installInitialLocation(in: pageVC)
      }

      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        !context.coordinator.hasActiveTurnSession,
        !context.coordinator.isAnimating,
        !(pageVC.transitionCoordinator?.isAnimated ?? false),
        targetChapterIndex >= 0,
        targetChapterIndex < viewModel.chapterCount,
        targetChapterIndex != context.coordinator.currentChapterIndex
          || targetPageIndex != context.coordinator.currentPageIndex
      {
        context.coordinator.performProgrammaticTurn(
          chapterIndex: targetChapterIndex,
          pageIndex: targetPageIndex,
          in: pageVC
        )
      }

      context.coordinator.reconfigureHosts()
    }

    private func pageCurlBacksideStyle() -> PageCurlBacksideViewController.Style {
      PageCurlBacksideViewController.Style(
        baseColor: preferences.resolvedTheme(for: colorScheme).uiColorBackground
      )
    }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: viewModel.publicationLanguage,
        readingProgression: viewModel.publicationReadingProgression
      )
    }

    private var pageCurlSpineLocation: UIPageViewController.SpineLocation {
      paginationLayout.reversesHorizontalGestureDirection ? .max : .min
    }

    private var pageCurlSemanticContentAttribute: UISemanticContentAttribute {
      paginationLayout.reversesHorizontalGestureDirection ? .forceRightToLeft : .forceLeftToRight
    }

    private func pageCurlNavigationDirection(forward: Bool) -> UIPageViewController.NavigationDirection {
      if paginationLayout.reversesHorizontalGestureDirection {
        return forward ? .reverse : .forward
      }
      return forward ? .forward : .reverse
    }

    private func pageCurlControllers(
      primary: UIViewController,
      backside: UIViewController,
      animated: Bool,
      in pageVC: UIPageViewController
    ) -> [UIViewController] {
      PageCurlControllerPlanner.controllers(
        primary: primary,
        animated: animated,
        in: pageVC,
        makeBackside: { backside }
      )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
      UIGestureRecognizerDelegate
    {
      var parent: WebPubPagedCurlView
      var currentChapterIndex: Int
      var currentPageIndex: Int
      var isAnimating = false
      weak var pageViewController: UIPageViewController?
      weak var tapGestureRecognizer: UITapGestureRecognizer?
      weak var longPressGestureRecognizer: UILongPressGestureRecognizer?
      var hasCompletedInitialUpdate = false

      private(set) var currentChapterController: EpubPageViewController?
      private var nextChapterController: EpubPageViewController?
      private var previousChapterController: EpubPageViewController?
      private var nextParkedShell: CurlPageShellViewController?
      private var previousParkedShell: CurlPageShellViewController?
      private var frontShell: CurlPageShellViewController?
      private var turnSession: TurnSession?
      var hasActiveTurnSession: Bool { turnSession != nil }

      private struct TurnTarget {
        let controller: EpubPageViewController
        let chapterIndex: Int
        let subPageIndex: Int
        let isCrossChapter: Bool
        let isForward: Bool
      }

      private struct TurnSession {
        let isInteractive: Bool
        let target: TurnTarget
        let targetShell: CurlPageShellViewController
        let leafShell: CurlPageShellViewController
        let leafSnapshot: UIView?
        let backside: PageCurlBacksideViewController
        let originPage: Int
      }

      private typealias PageTarget = EpubPageTarget

      // Backward flips need the target page's image synchronously, but the
      // target's controller may not render it in time; pages are captured as
      // they become the committed page so a back-flip can read them offhand.
      private let maxCachedBacksideSnapshots = 6
      private var cachedBacksideImages: [String: UIImage] = [:]
      private var cachedBacksideImageOrder: [String] = []
      private var backsideCaptureWorkItem: DispatchWorkItem?

      private var paginationLayout: WebPubPaginationLayout {
        parent.paginationLayout
      }

      init(_ parent: WebPubPagedCurlView) {
        self.parent = parent
        self.currentChapterIndex = parent.viewModel.currentChapterIndex
        self.currentPageIndex = parent.viewModel.currentPageIndex
      }

      // MARK: - Installation

      // While the book is loading, the view model's location is not resolved
      // yet; installing it would pin the coordinator to a stale page that a
      // later restore can fail to replace (a programmatic turn is dropped
      // while the presentation transition is still running).
      func installInitialLocation(in pageVC: UIPageViewController) {
        let chapterIndex = parent.viewModel.currentChapterIndex
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        let pageIndex = max(0, min(parent.viewModel.currentPageIndex, pageCount - 1))
        guard chapterIndex >= 0,
          chapterIndex < parent.viewModel.chapterCount,
          !parent.viewModel.isLoading,
          let controller = makeChapterController(chapterIndex: chapterIndex, subPageIndex: pageIndex)
        else {
          PageCurlControllerPlanner.safeSetViewControllers(
            PageCurlControllerPlanner.placeholderControllers(
              in: pageVC,
              backgroundColor: parent.preferences.resolvedTheme(for: parent.colorScheme).uiColorBackground
            ),
            on: pageVC,
            direction: .forward,
            animated: false
          )
          return
        }
        installCurrent(controller, in: pageVC)
        commitLocation(chapterIndex: chapterIndex, pageIndex: pageIndex, notify: false)
      }

      private func installCurrent(_ controller: EpubPageViewController, in pageVC: UIPageViewController) {
        currentChapterController = controller
        controller.loadViewIfNeeded()
        controller.forceEnsureContentLoaded()
        let shell = CurlPageShellViewController()
        shell.view.frame = pageVC.view.bounds
        shell.adopt(controller)
        frontShell = shell
        PageCurlControllerPlanner.safeSetViewControllers(
          [shell],
          on: pageVC,
          direction: .forward,
          animated: false
        )
        refreshNeighbors()
      }

      // MARK: - Chapter hosts

      private var pageControllerFactory: EpubPageControllerFactory {
        EpubPageControllerFactory(
          viewModel: parent.viewModel,
          renderingEngine: parent.renderingEngine,
          preferences: parent.preferences,
          colorScheme: parent.colorScheme,
          overlayPreferences: parent.overlayPreferences,
          showingControls: parent.showingControls,
          bookTitle: parent.bookTitle
        )
      }

      func makeChapterController(
        chapterIndex: Int,
        subPageIndex: Int,
        preferLastPageOnReady: Bool = false
      ) -> EpubPageViewController? {
        guard
          let controller = pageControllerFactory.makeController(
            chapterIndex: chapterIndex,
            subPageIndex: subPageIndex,
            preferLastPageOnReady: preferLastPageOnReady
          )
        else { return nil }
        wireController(controller)
        controller.onLinkTap = { [weak self] url in
          self?.parent.viewModel.navigateToURL(url)
        }
        controller.loadViewIfNeeded()
        return controller
      }

      private func wireController(_ controller: EpubPageViewController) {
        controller.onRepagination = { [weak self] in
          self?.invalidateBacksideCache()
        }
        controller.onPageIndexAdjusted = { [weak self, weak controller] pageIndex in
          guard let self, let controller else { return }
          guard self.currentChapterController === controller, self.turnSession == nil else { return }
          let chapterIndex = controller.chapterIndex
          let storedCount = self.parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
          let effectiveCount = max(storedCount, controller.totalPagesInChapter)
          let normalizedPageIndex = max(0, min(pageIndex, effectiveCount - 1))
          if effectiveCount != storedCount {
            self.parent.viewModel.updateChapterPageCount(effectiveCount, for: chapterIndex)
          }
          self.parent.viewModel.currentChapterIndex = chapterIndex
          self.parent.viewModel.currentPageIndex = normalizedPageIndex
          self.parent.viewModel.targetChapterIndex = nil
          self.parent.viewModel.targetPageIndex = nil
          self.currentChapterIndex = chapterIndex
          self.currentPageIndex = normalizedPageIndex
          self.parent.viewModel.pageDidChange()
        }
      }

      private func reconfigureHost(_ controller: EpubPageViewController) {
        pageControllerFactory.reconfigure(controller)
      }

      func reconfigureHosts() {
        if let currentChapterController { reconfigureHost(currentChapterController) }
        if let nextChapterController { reconfigureHost(nextChapterController) }
        if let previousChapterController { reconfigureHost(previousChapterController) }
      }

      // MARK: - Neighbor preloading

      private func nextPageTarget(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> PageTarget? {
        EpubPageTargetResolver.next(
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          viewModel: parent.viewModel
        )
      }

      private func previousPageTarget(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> PageTarget? {
        EpubPageTargetResolver.previous(
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          viewModel: parent.viewModel
        )
      }

      // Neighbor chapters are parked inside the front shell so they load and
      // paginate at the final geometry before the user turns to them; an
      // off-window web view does neither and would start both mid-turn.
      private func parkNeighbor(_ controller: EpubPageViewController, isNext: Bool) {
        guard let frontShell else { return }
        let slot = isNext ? nextParkedShell : previousParkedShell
        if let slot, slot.children.first === controller, slot.view.window != nil { return }
        slot?.unpark()
        let shell = CurlPageShellViewController()
        shell.view.frame = frontShell.view.bounds
        shell.view.isUserInteractionEnabled = false
        shell.adopt(controller)
        frontShell.addChild(shell)
        frontShell.view.insertSubview(shell.view, at: 0)
        shell.didMove(toParent: frontShell)
        if isNext {
          nextParkedShell = shell
        } else {
          previousParkedShell = shell
        }
      }

      private func unparkNeighbor(isNext: Bool) {
        if isNext {
          nextParkedShell?.unpark()
          nextParkedShell = nil
        } else {
          previousParkedShell?.unpark()
          previousParkedShell = nil
        }
      }

      private func unparkIfParked(_ controller: EpubPageViewController) {
        if nextParkedShell?.children.first === controller {
          nextParkedShell?.unpark()
          nextParkedShell = nil
        }
        if previousParkedShell?.children.first === controller {
          previousParkedShell?.unpark()
          previousParkedShell = nil
        }
      }

      private func refreshNeighbors(reusing detached: [EpubPageViewController] = []) {
        guard let current = currentChapterController else { return }
        let chapterIndex = current.chapterIndex
        // Coordinator position fields still hold the previous location until commitLocation runs.
        let subPageIndex = current.currentSubPageIndex

        if let nextTarget = nextPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          nextTarget.chapterIndex != chapterIndex
        {
          if nextChapterController?.chapterIndex != nextTarget.chapterIndex {
            let host =
              detached.first { $0.chapterIndex == nextTarget.chapterIndex }
              ?? makeChapterController(
                chapterIndex: nextTarget.chapterIndex,
                subPageIndex: nextTarget.subPageIndex,
                preferLastPageOnReady: nextTarget.preferLastPage
              )
            if let host {
              if host.currentSubPageIndex != nextTarget.subPageIndex, !nextTarget.preferLastPage {
                host.scrollToPageIndex(nextTarget.subPageIndex)
              }
              host.loadViewIfNeeded()
              host.forceEnsureContentLoaded()
            }
            nextChapterController = host
          }
          if let host = nextChapterController {
            parkNeighbor(host, isNext: true)
          }
        } else {
          nextChapterController = nil
          unparkNeighbor(isNext: true)
        }

        if let prevTarget = previousPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          prevTarget.chapterIndex != chapterIndex
        {
          if previousChapterController?.chapterIndex != prevTarget.chapterIndex {
            let host =
              detached.first { $0.chapterIndex == prevTarget.chapterIndex }
              ?? makeChapterController(
                chapterIndex: prevTarget.chapterIndex,
                subPageIndex: prevTarget.subPageIndex,
                preferLastPageOnReady: prevTarget.preferLastPage
              )
            if let host {
              if host.currentSubPageIndex != prevTarget.subPageIndex, !prevTarget.preferLastPage {
                host.scrollToPageIndex(prevTarget.subPageIndex)
              }
              host.loadViewIfNeeded()
              host.forceEnsureContentLoaded()
            }
            previousChapterController = host
          }
          if let host = previousChapterController {
            parkNeighbor(host, isNext: false)
          }
        } else {
          previousChapterController = nil
          unparkNeighbor(isNext: false)
        }
      }

      // MARK: - Turns

      private func prepareTurnTarget(
        chapterIndex: Int,
        subPageIndex: Int,
        preferLastPageOnReady: Bool,
        isForward: Bool
      ) -> TurnTarget? {
        guard let current = currentChapterController else { return nil }
        if chapterIndex == current.chapterIndex {
          return TurnTarget(
            controller: current,
            chapterIndex: chapterIndex,
            subPageIndex: subPageIndex,
            isCrossChapter: false,
            isForward: isForward
          )
        }
        let neighbor: EpubPageViewController?
        if nextChapterController?.chapterIndex == chapterIndex {
          neighbor = nextChapterController
        } else if previousChapterController?.chapterIndex == chapterIndex {
          neighbor = previousChapterController
        } else {
          neighbor = nil
        }
        guard
          let host = neighbor
            ?? makeChapterController(
              chapterIndex: chapterIndex,
              subPageIndex: subPageIndex,
              preferLastPageOnReady: preferLastPageOnReady
            )
        else { return nil }
        // An explicit turn supersedes restoration anchors retained by a reused chapter.
        host.targetProgressionOnReady = nil
        var resolvedSubPageIndex = subPageIndex
        if preferLastPageOnReady {
          if host.isContentLoaded {
            resolvedSubPageIndex = max(0, host.totalPagesInChapter - 1)
            host.preferLastPageOnReady = false
            host.scrollToPageIndex(resolvedSubPageIndex)
          } else {
            host.preferLastPageOnReady = true
          }
        } else {
          host.preferLastPageOnReady = false
          host.scrollToPageIndex(subPageIndex)
        }
        return TurnTarget(
          controller: host,
          chapterIndex: chapterIndex,
          subPageIndex: resolvedSubPageIndex,
          isCrossChapter: true,
          isForward: isForward
        )
      }

      private func makeTurnSession(
        target: TurnTarget,
        originPage: Int,
        isInteractive: Bool,
        onReady: @escaping (TurnSession?) -> Void
      ) {
        guard let pageVC = pageViewController, let leaf = frontShell else {
          onReady(nil)
          return
        }
        let targetShell = CurlPageShellViewController()
        // Pre-size so the hosted web view never passes through a zero-size layout,
        // which would trigger a throwaway re-pagination.
        targetShell.view.frame = pageVC.view.bounds

        func makeSession(
          snapshot: UIView?,
          mirror: PageCurlBacksideViewController.MirroredSnapshot?
        ) -> TurnSession {
          TurnSession(
            isInteractive: isInteractive,
            target: target,
            targetShell: targetShell,
            leafShell: leaf,
            leafSnapshot: snapshot,
            backside: PageCurlBacksideViewController(
              destinationToken: "\(target.chapterIndex):\(target.subPageIndex)",
              style: parent.pageCurlBacksideStyle(),
              mirroredSnapshot: mirror
            ),
            originPage: originPage
          )
        }

        if target.isCrossChapter {
          target.controller.loadViewIfNeeded()
          target.controller.forceEnsureContentLoaded()
          let (mirror, capturedTarget) = crossChapterMirror(target: target)
          unparkIfParked(target.controller)
          targetShell.adopt(target.controller)
          let session = makeSession(snapshot: nil, mirror: mirror)
          onReady(session)
          if !target.isForward && !capturedTarget {
            // The neighbor is still loading or paginating toward the target
            // page; capture the backside once it becomes ready.
            target.controller.onPaginationReady = {
              [weak self, weak controller = target.controller, weak backside = session.backside] in
              controller?.onPaginationReady = nil
              guard let self, let controller, let backside,
                self.turnSession?.backside === backside,
                let image = controller.makeBacksideSnapshotImage()
              else { return }
              backside.updateMirroredSnapshot(
                PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal)
              )
            }
          }
          return
        }

        guard let current = currentChapterController,
          let snapshot = current.view.snapshotView(afterScreenUpdates: false)
        else {
          onReady(nil)
          return
        }
        let mirror: PageCurlBacksideViewController.MirroredSnapshot?
        if !target.isForward,
          let cached = cachedBacksideImage(chapterIndex: target.chapterIndex, pageIndex: target.subPageIndex)
        {
          mirror = PageCurlBacksideViewController.makeMirroredSnapshot(from: cached, axis: .horizontal)
        } else {
          mirror = PageCurlBacksideViewController.makeMirroredSnapshot(from: current, axis: .horizontal)
        }
        leaf.pin(snapshot)
        if isInteractive {
          targetShell.adopt(current)
          let session = makeSession(snapshot: snapshot, mirror: mirror)
          onReady(session)
          if target.isForward {
            current.scrollToPageIndex(target.subPageIndex)
          } else {
            // A backward flip's backside mirrors the target page, whose pixels
            // exist only once the live view has scrolled there.
            current.scrollToPageIndexAndSettle(target.subPageIndex) {
              [weak self, weak current, weak backside = session.backside] in
              guard let self, let current, let backside,
                self.turnSession?.backside === backside,
                let image = current.makeBacksideSnapshotImage()
              else { return }
              backside.updateMirroredSnapshot(
                PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal)
              )
            }
          }
        } else {
          // A programmatic curl samples the live view from its first frame, so the
          // view must already show the target page; it keeps rendering under the
          // leaf snapshot, keeping the early scroll invisible.
          current.scrollToPageIndexAndSettle(target.subPageIndex) {
            let targetMirror =
              !target.isForward
              ? (current.makeBacksideSnapshotImage()
                ?? self.cachedBacksideImage(chapterIndex: target.chapterIndex, pageIndex: target.subPageIndex))
                .flatMap {
                  PageCurlBacksideViewController.makeMirroredSnapshot(from: $0, axis: .horizontal)
                }
              : nil
            targetShell.adopt(current)
            onReady(makeSession(snapshot: snapshot, mirror: targetMirror ?? mirror))
          }
        }
      }

      private func crossChapterMirror(
        target: TurnTarget
      ) -> (mirror: PageCurlBacksideViewController.MirroredSnapshot?, capturedTarget: Bool) {
        if !target.isForward,
          let image = cachedBacksideImage(chapterIndex: target.chapterIndex, pageIndex: target.subPageIndex)
            ?? target.controller.makeBacksideSnapshotImage()
        {
          return (
            PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal),
            true
          )
        }
        guard let current = currentChapterController else { return (nil, false) }
        return (
          PageCurlBacksideViewController.makeMirroredSnapshot(from: current, axis: .horizontal),
          false
        )
      }

      private func backsideCacheKey(chapterIndex: Int, pageIndex: Int) -> String {
        "\(chapterIndex)-\(pageIndex)"
      }

      private func cachedBacksideImage(chapterIndex: Int, pageIndex: Int) -> UIImage? {
        let key = backsideCacheKey(chapterIndex: chapterIndex, pageIndex: pageIndex)
        guard let image = cachedBacksideImages[key] else { return nil }
        cachedBacksideImageOrder.removeAll { $0 == key }
        cachedBacksideImageOrder.append(key)
        return image
      }

      private func storeBacksideImage(_ image: UIImage, chapterIndex: Int, pageIndex: Int) {
        let key = backsideCacheKey(chapterIndex: chapterIndex, pageIndex: pageIndex)
        cachedBacksideImages[key] = image
        cachedBacksideImageOrder.removeAll { $0 == key }
        cachedBacksideImageOrder.append(key)
        while cachedBacksideImageOrder.count > maxCachedBacksideSnapshots {
          let removedKey = cachedBacksideImageOrder.removeFirst()
          cachedBacksideImages.removeValue(forKey: removedKey)
        }
      }

      private func invalidateBacksideCache() {
        backsideCaptureWorkItem?.cancel()
        cachedBacksideImages.removeAll()
        cachedBacksideImageOrder.removeAll()
      }

      private func scheduleBacksideImageCapture(chapterIndex: Int, pageIndex: Int) {
        backsideCaptureWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
          guard let self,
            let controller = self.currentChapterController,
            controller.chapterIndex == chapterIndex,
            controller.currentSubPageIndex == pageIndex,
            self.turnSession == nil,
            !self.isAnimating,
            let image = controller.makeBacksideSnapshotImage()
          else { return }
          self.storeBacksideImage(image, chapterIndex: chapterIndex, pageIndex: pageIndex)
        }
        backsideCaptureWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
      }

      func performProgrammaticTurn(chapterIndex: Int, pageIndex: Int, in pageVC: UIPageViewController) {
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        let isLastPageRequest = pageIndex < 0
        let normalizedPageIndex =
          isLastPageRequest
          ? max(0, pageCount - 1)
          : max(0, min(pageIndex, pageCount - 1))
        let isForward =
          chapterIndex > currentChapterIndex
          || (chapterIndex == currentChapterIndex && normalizedPageIndex > currentPageIndex)

        guard
          let target = prepareTurnTarget(
            chapterIndex: chapterIndex,
            subPageIndex: normalizedPageIndex,
            preferLastPageOnReady: isLastPageRequest,
            isForward: isForward
          )
        else { return }

        let shouldAnimate = hasCompletedInitialUpdate && parent.animateTapTurns
        if shouldAnimate {
          isAnimating = true
          makeTurnSession(
            target: target,
            originPage: currentPageIndex,
            isInteractive: false
          ) { [weak self] session in
            guard let self else { return }
            guard let session else {
              self.isAnimating = false
              self.installTurnTarget(target, in: pageVC)
              self.commitLocation(
                chapterIndex: target.chapterIndex,
                pageIndex: target.controller.currentSubPageIndex,
                notify: true
              )
              return
            }
            self.turnSession = session
            let controllers = self.parent.pageCurlControllers(
              primary: session.targetShell,
              backside: session.backside,
              animated: true,
              in: pageVC
            )
            PageCurlControllerPlanner.safeSetViewControllers(
              controllers,
              on: pageVC,
              direction: self.parent.pageCurlNavigationDirection(forward: isForward),
              animated: true
            ) { [weak self] completed in
              guard let self, let session = self.turnSession else { return }
              self.isAnimating = false
              if completed {
                self.commitTurnSession(session, in: pageVC)
              } else {
                self.cancelTurnSession(session)
              }
            }
          }
        } else {
          installTurnTarget(target, in: pageVC)
          commitLocation(
            chapterIndex: target.chapterIndex,
            pageIndex: target.controller.currentSubPageIndex,
            notify: true
          )
        }
      }

      private func installTurnTarget(_ target: TurnTarget, in pageVC: UIPageViewController) {
        if target.isCrossChapter {
          let detached = [currentChapterController, nextChapterController, previousChapterController]
            .compactMap { $0 }
            .filter { $0 !== target.controller }
          currentChapterController = target.controller
          nextChapterController = nil
          previousChapterController = nil
          target.controller.loadViewIfNeeded()
          target.controller.forceEnsureContentLoaded()
          unparkIfParked(target.controller)
          let shell = CurlPageShellViewController()
          shell.view.frame = pageVC.view.bounds
          shell.adopt(target.controller)
          frontShell = shell
          PageCurlControllerPlanner.safeSetViewControllers(
            [shell],
            on: pageVC,
            direction: .forward,
            animated: false
          )
          refreshNeighbors(reusing: detached)
        } else {
          if target.controller.targetProgressionOnReady == nil {
            target.controller.scrollToPageIndex(target.subPageIndex)
          }
          refreshNeighbors()
        }
      }

      private func commitTurnSession(_ session: TurnSession, in pageVC: UIPageViewController) {
        turnSession = nil
        if pageVC.viewControllers?.first !== session.targetShell {
          PageCurlControllerPlanner.safeSetViewControllers(
            [session.targetShell],
            on: pageVC,
            direction: .forward,
            animated: false
          )
        }
        frontShell = session.targetShell
        if session.target.isCrossChapter {
          let detached = [currentChapterController, nextChapterController, previousChapterController]
            .compactMap { $0 }
            .filter { $0 !== session.target.controller }
          currentChapterController = session.target.controller
          nextChapterController = nil
          previousChapterController = nil
          refreshNeighbors(reusing: detached)
        } else {
          refreshNeighbors()
        }
        commitLocation(
          chapterIndex: session.target.chapterIndex,
          pageIndex: session.target.controller.currentSubPageIndex,
          notify: true
        )
      }

      private func cancelTurnSession(_ session: TurnSession) {
        turnSession = nil
        guard !session.target.isCrossChapter else { return }
        guard let current = currentChapterController else {
          session.leafSnapshot?.removeFromSuperview()
          return
        }
        session.leafShell.adopt(current)
        // Keep the leaf snapshot on top until the live view has scrolled back to it.
        current.scrollToPageIndex(session.originPage) {
          session.leafSnapshot?.removeFromSuperview()
        }
      }

      func commitLocation(chapterIndex: Int, pageIndex: Int, notify: Bool) {
        currentChapterIndex = chapterIndex
        currentPageIndex = pageIndex
        scheduleBacksideImageCapture(chapterIndex: chapterIndex, pageIndex: pageIndex)
        guard notify else {
          if parent.viewModel.currentChapterIndex != chapterIndex {
            parent.viewModel.currentChapterIndex = chapterIndex
          }
          if parent.viewModel.currentPageIndex != pageIndex {
            parent.viewModel.currentPageIndex = pageIndex
          }
          // An install that lands on the pending target fulfills it. Leaving
          // it set would fire a spurious turn back here once the restored
          // page jump moves the coordinator past it.
          if parent.viewModel.targetChapterIndex == chapterIndex,
            parent.viewModel.targetPageIndex == pageIndex
          {
            parent.viewModel.targetChapterIndex = nil
            parent.viewModel.targetPageIndex = nil
          }
          return
        }
        Task { @MainActor in
          if let controller = currentChapterController {
            controller.preferLastPageOnReady = false
            controller.targetProgressionOnReady = nil
          }
          parent.viewModel.currentChapterIndex = chapterIndex
          parent.viewModel.currentPageIndex = pageIndex
          parent.viewModel.targetChapterIndex = nil
          parent.viewModel.targetPageIndex = nil
          parent.viewModel.pageDidChange()
        }
      }

      // MARK: - UIPageViewControllerDataSource

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        dataSourceSibling(after: false, of: viewController, in: pageViewController)
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        dataSourceSibling(after: true, of: viewController, in: pageViewController)
      }

      private func dataSourceSibling(
        after: Bool,
        of viewController: UIViewController,
        in pageVC: UIPageViewController
      ) -> UIViewController? {
        if viewController is PageCurlBacksideViewController {
          return turnSession?.targetShell
        }
        guard viewController === frontShell,
          turnSession == nil,
          !isAnimating,
          let current = currentChapterController
        else { return nil }

        let target =
          after
          ? pageViewControllerAfterTarget(from: current)
          : pageViewControllerBeforeTarget(from: current)
        guard let target else { return nil }

        let isForward =
          target.chapterIndex > current.chapterIndex
          || (target.chapterIndex == current.chapterIndex && target.subPageIndex > currentPageIndex)
        guard
          let turnTarget = prepareTurnTarget(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            preferLastPageOnReady: target.preferLastPage,
            isForward: isForward
          )
        else { return nil }

        // Interactive sessions are always ready synchronously; UIPageViewController
        // cannot wait for an async session while a gesture is starting.
        var session: TurnSession?
        makeTurnSession(target: turnTarget, originPage: currentPageIndex, isInteractive: true) {
          session = $0
        }
        guard let session else { return nil }

        turnSession = session
        return session.backside
      }

      private func pageViewControllerBeforeTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return nextPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
        }
        return previousPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
      }

      private func pageViewControllerAfterTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return previousPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
        }
        return nextPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
      }

      // MARK: - UIPageViewControllerDelegate

      func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        guard !pendingViewControllers.isEmpty else { return }
        isAnimating = true
        for controller in pendingViewControllers {
          if let backside = controller as? PageCurlBacksideViewController {
            backside.updateStyle(parent.pageCurlBacksideStyle())
          }
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
      ) {
        guard let session = turnSession, session.isInteractive else { return }
        isAnimating = false
        if completed {
          commitTurnSession(session, in: pageViewController)
        } else {
          cancelTurnSession(session)
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
      ) -> UIPageViewController.SpineLocation {
        parent.pageCurlSpineLocation
      }

      // MARK: - Tap Handling

      @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isAnimating else { return }
        if let current = currentChapterController,
          current.handleLinkTap(at: recognizer.location(in: current.view))
        {
          return
        }
        let location = recognizer.location(in: recognizer.view)
        let size = recognizer.view?.bounds.size ?? .zero
        guard size.width > 0, size.height > 0 else { return }

        let normalizedX = location.x / size.width
        let normalizedY = location.y / size.height

        let action = TapZoneHelper.action(
          normalizedX: normalizedX,
          normalizedY: normalizedY,
          tapZoneMode: AppConfig.epubTapZoneMode,
          tapZoneInversionMode: AppConfig.epubTapZoneInversionMode,
          readingDirection: tapReadingDirection()
        )

        switch action {
        case .previous:
          parent.viewModel.goToPreviousPage()
        case .next:
          if isAtLastPage() {
            parent.onEndReached()
          } else {
            parent.viewModel.goToNextPage()
          }
        case .toggleControls:
          parent.onCenterTap()
        }
      }

      @objc func handleLongPress(_: UILongPressGestureRecognizer) {}

      private func tapReadingDirection() -> ReadingDirection {
        switch parent.viewModel.publicationReadingProgression {
        case .rtl:
          return .rtl
        case .ttb, .btt:
          return .vertical
        case .ltr, .auto, .none:
          return .ltr
        }
      }

      private func isAtLastPage() -> Bool {
        guard let current = currentChapterController else { return false }
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        guard current.chapterIndex == lastChapterIndex else { return false }
        let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
        let pageCount = max(storedCount, current.totalPagesInChapter)
        return currentPageIndex >= pageCount - 1
      }

      // MARK: - UIGestureRecognizerDelegate

      @objc func handleInternalPanState(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
          // A dataSource prefetch that never became a curl leaves a session behind.
          if !isAnimating, let session = turnSession, session.isInteractive {
            cancelTurnSession(session)
          }
        default:
          break
        }
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pageVC = pageViewController,
          let current = currentChapterController
        else {
          return true
        }

        if gestureRecognizer === tapGestureRecognizer || gestureRecognizer === longPressGestureRecognizer {
          return true
        }

        // Check if this is UIPageViewController's internal gesture
        guard gestureRecognizer.view === pageVC.view || gestureRecognizer.view?.superview === pageVC.view else {
          return true
        }

        let isAtFirstPage = current.chapterIndex == 0 && currentPageIndex <= 0
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        let atLastPage: Bool = {
          if current.chapterIndex == lastChapterIndex {
            let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
            let pageCount = max(storedCount, current.totalPagesInChapter)
            return currentPageIndex >= pageCount - 1
          }
          return false
        }()

        // For tap gestures, check tap location
        if let tapGesture = gestureRecognizer as? UITapGestureRecognizer {
          let location = tapGesture.location(in: pageVC.view)
          let viewWidth = pageVC.view.bounds.width
          let tapZoneWidth = viewWidth * 0.3

          let isPreviousTap =
            paginationLayout.reversesHorizontalGestureDirection
            ? location.x > viewWidth - tapZoneWidth
            : location.x < tapZoneWidth
          let isNextTap =
            paginationLayout.reversesHorizontalGestureDirection
            ? location.x < tapZoneWidth
            : location.x > viewWidth - tapZoneWidth

          if isAtFirstPage && isPreviousTap {
            return false
          }

          if atLastPage && isNextTap {
            parent.onEndReached()
            return false
          }
        } else if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
          let translation = panGesture.translation(in: pageVC.view)
          let velocity = panGesture.velocity(in: pageVC.view)
          let directionSignal = horizontalGestureDirectionSignal(
            translationX: translation.x,
            velocityX: velocity.x
          )

          if directionSignal == 0 {
            return !isAtFirstPage && !atLastPage
          }

          if horizontalGestureSignalIsForward(directionSignal) {
            if atLastPage {
              parent.onEndReached()
              return false
            }
          } else if isAtFirstPage {
            return false
          }
        }

        return true
      }

      private func horizontalGestureDirectionSignal(
        translationX: CGFloat,
        velocityX: CGFloat
      ) -> CGFloat {
        if abs(translationX) >= 1 {
          return translationX
        }
        if abs(velocityX) >= 60 {
          return velocityX
        }
        return 0
      }

      private func horizontalGestureSignalIsForward(_ signal: CGFloat) -> Bool {
        paginationLayout.reversesHorizontalGestureDirection ? signal > 0 : signal < 0
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view is UIControl {
          return false
        }
        return true
      }
    }
  }
#endif
